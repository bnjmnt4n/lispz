const std = @import("std");
const zinput = @import("zinput");
const utils = @import("utils.zig");

const LObject = union(enum) {
    Fixnum: i64,
    Boolean: bool,
    Symbol: []const u8,
    Nil,
    // TODO: figure out the differences between *const LObject and *LObject.
    Pair: [2]*LObject,

    fn getValue(self: LObject, comptime tag: std.meta.Tag(LObject)) ?std.meta.TagPayload(LObject, tag) {
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

    var environmentValue: LObject = LObject.Nil;
    var environment = &environmentValue;

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
        var sexp = parser.getValue() catch |err| {
            switch (err) {
                error.UnexpectedEndOfContent => std.debug.print("No value provided.\n", .{}),
                error.UnexpectedValue => std.debug.print("Unrecognized value.\n", .{}),
                error.Overflow => std.debug.print("Number is too large.\n", .{}),
                else => std.debug.print("Unexpected error.\n", .{}),
            }
            continue;
        };

        const evalResult = evalSexp(allocator, &sexp, environment) catch |err| switch (err) {
            error.NotFound => {
                std.debug.print("Couldn't find value.\n", .{});
                continue;
            },
            else => {
                std.debug.print("Error evaluating value.\n", .{});
                continue;
            },
        };

        const evaluatedSexp = evalResult[0];
        environment = evalResult[1];

        const printedSexp = printSexp(allocator, evaluatedSexp.*) catch |err| {
            std.debug.print("Error printing value.\n", .{});
            continue;
        };

        std.debug.print("{s}\n", .{printedSexp});
    }
}

const EvaluationError = error{
    NotFound,
    UnexpectedIfCondition,
} || std.mem.Allocator.Error;

fn evalSexp(allocator: *std.mem.Allocator, sexp: *LObject, environment: *LObject) EvaluationError![2]*LObject {
    return switch (sexp.*) {
        .Nil => .{ sexp, environment },
        .Fixnum => .{ sexp, environment },
        .Boolean => .{ sexp, environment },
        .Symbol => |name| .{ try lookup(name, environment), environment },
        .Pair => |pair| blk: {
            const defaultExpr = [2]*LObject{ sexp, environment };

            const symbol = pair[0].getValue(.Symbol) orelse break :blk defaultExpr;

            if (std.mem.eql(u8, symbol, "env")) {
                const nextPair = pair[1].getValue(.Nil) orelse break :blk defaultExpr;
                break :blk [2]*LObject{ environment, environment };
            }

            const nextPair = pair[1].getValue(.Pair) orelse break :blk defaultExpr;
            const condition = nextPair[0];
            const nextPair2 = nextPair[1].getValue(.Pair) orelse break :blk defaultExpr;
            const consequent = nextPair2[0];

            if (std.mem.eql(u8, symbol, "val")) {
                // Assert end.
                _ = nextPair2[1].getValue(.Nil) orelse break :blk defaultExpr;
                const variableName = condition.getValue(.Symbol) orelse break :blk defaultExpr;

                var result = try evalSexp(allocator, consequent, environment);
                const variableValue = result[0];
                const newEnvironment = result[1];

                const newEnvironment2 = try bind(allocator, variableName, variableValue, newEnvironment);

                break :blk [2]*LObject{ variableValue, newEnvironment2 };
            }

            if (std.mem.eql(u8, symbol, "pair")) {
                // Assert end.
                _ = nextPair2[1].getValue(.Nil) orelse break :blk defaultExpr;
                const car = condition;
                const cdr = consequent;

                var newPair = try allocator.create(LObject);
                newPair.* = LObject{ .Pair = .{ car, cdr } };

                break :blk [2]*LObject{ newPair, environment };
            }

            const nextPair3 = nextPair2[1].getValue(.Pair) orelse break :blk defaultExpr;
            const alternate = nextPair3[0];
            const end = nextPair3[1].getValue(.Nil) orelse break :blk defaultExpr;

            if (std.mem.eql(u8, symbol, "if")) {
                var result = try evalSexp(allocator, condition, environment);
                const conditionValue = result[0].getValue(.Boolean) orelse return error.UnexpectedIfCondition;
                const newEnvironment = result[1];
                switch (conditionValue) {
                    true => break :blk [2]*LObject{ consequent, newEnvironment },
                    false => break :blk [2]*LObject{ alternate, newEnvironment },
                }
            }

            break :blk defaultExpr;
        },
    };
}

fn bind(allocator: *std.mem.Allocator, name: []const u8, value: *LObject, environment: *LObject) !*LObject {
    var symbol = try allocator.create(LObject);
    symbol.* = LObject{ .Symbol = name };

    var nameValuePair = try allocator.create(LObject);
    nameValuePair.* = LObject{ .Pair = .{ symbol, value } };

    var newEnvironment = try allocator.create(LObject);
    newEnvironment.* = LObject{ .Pair = .{ nameValuePair, environment } };
    return newEnvironment;
}

fn lookup(name: []const u8, environment: *LObject) !*LObject {
    switch (environment.*) {
        .Nil => return error.NotFound,
        .Pair => |pair| {
            const nameValuePair = pair[0].getValue(.Pair) orelse unreachable;
            const nameSymbol = nameValuePair[0].getValue(.Symbol) orelse unreachable;

            if (std.mem.eql(u8, name, nameSymbol)) return nameValuePair[1];
            return lookup(name, pair[1]);
        },
        else => unreachable,
    }
}

const PrinterError = error{UnexpectedValue} || std.fmt.AllocPrintError;

fn printSexp(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    return switch (sexp) {
        .Symbol => |symbol| try std.fmt.allocPrint(allocator, "{s}", .{symbol}),
        .Fixnum => |num| try std.fmt.allocPrint(allocator, "{}", .{num}),
        .Boolean => |boolean| if (boolean) "#t" else "#f",
        // TODO: figure out context and print () only if embedded within a list?
        .Nil => "()",
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
    const pair = sexp.getValue(.Pair) orelse unreachable;

    return try std.fmt.allocPrint(allocator, "{s} . {s}", .{
        try printSexp(allocator, pair[0].*),
        try printSexp(allocator, pair[1].*),
    });
}

fn printList(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const pair = sexp.getValue(.Pair) orelse unreachable;
    const car = try printSexp(allocator, pair[0].*);

    const cdr = switch (pair[1].*) {
        .Nil => "",
        .Pair => try std.fmt.allocPrint(allocator, " {s}", .{
            try printList(allocator, pair[1].*),
        }),
        else => unreachable,
    };

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ car, cdr });
}

fn isList(sexp: LObject) bool {
    return switch (sexp) {
        .Nil => true,
        .Pair => |nextPair| isList(nextPair[1].*),
        else => false,
    };
}
