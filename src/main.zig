const std = @import("std");
const zinput = @import("zinput");
const utils = @import("utils.zig");

const LObject = union(enum) {
    Fixnum: i64,
    Boolean: bool,
    Symbol: []const u8,
    Nil,
    Pair: [2]*const LObject,

    fn getValue(self: LObject, comptime tag: std.meta.Tag(LObject)) ?utils.getUnionFieldType(LObject, tag) {
        return switch (self) {
            tag => @field(self, @tagName(tag)),
            else => null,
        };
    }
};

// Note: recursive functions cannot have inferred error sets.
// See https://github.com/ziglang/zig/issues/2971.
const ParserError = error{
    UnexpectedValue,
    UnexpectedEndOfContent,
} || std.fmt.ParseIntError || std.mem.Allocator.Error;

const Parser = struct {
    const Self = @This();

    input: []const u8,
    index: u8 = 0,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator, string: []const u8) Parser {
        return Self{
            .allocator = allocator,
            .input = string,
        };
    }

    fn isDone(self: Self) bool {
        return self.index >= self.input.len;
    }

    fn peek(self: Self) ?u8 {
        if (self.isDone()) {
            return null;
        }

        return self.input[self.index];
    }

    fn readCharacter(self: *Self) ?u8 {
        if (self.isDone()) {
            return null;
        }

        const char = self.input[self.index];
        self.index += 1;
        return char;
    }

    fn unreadCharacter(self: *Self) void {
        self.index = if (self.index <= 0) 0 else self.index - 1;
    }

    fn eatWhitespace(self: *Self) void {
        const char = self.readCharacter() orelse return;

        if (utils.isWhitespace(char)) {
            self.eatWhitespace();
        } else {
            self.unreadCharacter();
        }
    }

    fn readFixnum(self: *Self, isNegative: bool) ParserError!*LObject {
        if (isNegative) _ = self.readCharacter();

        const startIndex = self.index - 1;
        while (!self.isDone() and utils.isDigit(self.peek().?)) {
            _ = self.readCharacter();
        }
        const endIndex = self.index;

        const num = try std.fmt.parseInt(i64, self.input[startIndex..endIndex], 10);
        const fixnum = if (isNegative) -num else num;

        var node = try self.allocator.create(LObject);
        node.* = LObject{ .Fixnum = fixnum };
        return node;
    }

    fn readBoolean(self: *Self) ParserError!*LObject {
        const nextChar = self.readCharacter() orelse return error.UnexpectedValue;
        const boolean = switch (nextChar) {
            't' => true,
            'f' => false,
            else => return error.UnexpectedValue,
        };

        var node = try self.allocator.create(LObject);
        node.* = LObject{ .Boolean = boolean };
        return node;
    }

    fn readSymbol(self: *Self) ParserError!*LObject {
        const startIndex = self.index - 1;
        while (!self.isDone() and !utils.isDelimiter(self.peek().?)) {
            _ = self.readCharacter();
        }
        const endIndex = self.index;

        const symbol = self.input[startIndex..endIndex];
        var node = try self.allocator.create(LObject);
        node.* = LObject{ .Symbol = symbol };
        return node;
    }

    fn readList(self: *Self) ParserError!*LObject {
        self.eatWhitespace();

        const nextChar = self.peek() orelse return error.UnexpectedEndOfContent;

        var node = try self.allocator.create(LObject);

        if (nextChar == ')') {
            _ = self.readCharacter();
            node.* = LObject.Nil;
        } else {
            const car = try self.readSexp();
            const cdr = try self.readList();

            node.* = LObject{ .Pair = .{ car, cdr } };
        }

        return node;
    }

    fn readSexp(self: *Self) ParserError!*LObject {
        self.eatWhitespace();
        const char = self.readCharacter() orelse return error.UnexpectedEndOfContent;

        if (utils.isSymbolStartCharacter(char)) {
            return self.readSymbol();
        } else if (utils.isDigit(char) or char == '~') {
            const isNegative = char == '~';
            return self.readFixnum(isNegative);
        } else if (char == '(') {
            return self.readList();
        } else if (char == '#') {
            return self.readBoolean();
        } else {
            return error.UnexpectedValue;
        }
    }

    fn getValue(self: *Self) ParserError!LObject {
        const sexpPointer = try self.readSexp();

        self.eatWhitespace();
        if (!self.isDone()) {
            return error.UnexpectedValue;
        } else {
            return sexpPointer.*;
        }
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    // Read-Eval-Print-Loop
    while (true) {
        const string = zinput.askString(allocator, "> ", 128) catch |err| switch (err) {
            error.EndOfStream => {
                std.debug.print("^D\n", .{});
                return;
            },
            else => {
                std.debug.print("Unexpected error occured.\n", .{});
                return err;
            },
        };

        var parser = Parser.init(allocator, string);
        const sexp = parser.getValue() catch |err| {
            switch (err) {
                error.UnexpectedEndOfContent => std.debug.print("No value provided.\n", .{}),
                error.UnexpectedValue => std.debug.print("Unrecognized value.\n", .{}),
                error.Overflow => std.debug.print("Number is too large.\n", .{}),
                else => std.debug.print("Unexpected error.\n", .{}),
            }
            continue;
        };

        const printedSexp = printSexp(allocator, sexp) catch |err| {
            std.debug.print("Error printing value.\n", .{});
            continue;
        };

        std.debug.print("{s}\n", .{printedSexp});
    }
}

fn bind(allocator: *std.mem.Allocator, name: []const u8, value: *LObject, environment: *LObject) !*LObject {
    var name = try allocator.create(LObject);
    name.* = LObject{ .Symbol = name };

    var nameValuePair = try allocator.create(LObject);
    nameValuePair.* = LObject{ .Pair = .{ name, value } };

    var newEnvironment = try allocator.create(LObject);
    newEnvironment.* = LObject{ .Pair = .{ nameValuePair, environment } };
    return newEnvironment;
}

fn lookup(name: []const u8, environment: *LObject) !*LObject {
    switch (environment.*) {
        .Nil => return error.NotFound,
        .Pair => |slice| {
            const nameValuePair = slice[0].*.getValue(.Pair) orelse unreachable;
            const nameSymbol = nameValuePair[0].*.getValue(.Symbol) orelse unreachable;

            if (std.mem.eql(u8, name, nameSymbol)) return nameValuePair[1];
            return lookup(name, slice[1]);
        },
        else => unreachable,
    }
}

const PrinterError = error{UnexpectedValue} || std.fmt.AllocPrintError;

fn printSexp(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    return switch (sexp) {
        .Symbol => |symbol| try std.fmt.allocPrint(allocator, "{s}", .{symbol}),
        .Fixnum => |num| try std.fmt.allocPrint(allocator, "{}", .{num}),
        .Boolean => |boolean| try std.fmt.allocPrint(allocator, "{}", .{boolean}),
        .Nil => "nil",
        .Pair => {
            const content = if (isList(sexp))
                (try printList(allocator, sexp))
            else
                (try printPair(allocator, sexp));
            return try std.fmt.allocPrint(allocator, "({s})", .{content});
        },
    };
}

fn printPair(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const slice = sexp.getValue(.Pair) orelse unreachable;

    return try std.fmt.allocPrint(allocator, "{s} . {s}", .{
        try printSexp(allocator, slice[0].*),
        try printSexp(allocator, slice[1].*),
    });
}

fn printList(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const slice = sexp.getValue(.Pair) orelse unreachable;
    const car = try printSexp(allocator, slice[0].*);

    const cdr = switch (slice[1].*) {
        .Nil => "",
        .Pair => try std.fmt.allocPrint(allocator, " {s}", .{try printList(allocator, slice[1].*)}),
        else => unreachable,
    };

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ car, cdr });
}

fn isList(pair: LObject) bool {
    return switch (pair) {
        .Nil => true,
        .Pair => |slice| isList(slice[1].*),
        else => unreachable,
    };
}
