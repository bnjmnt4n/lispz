const std = @import("std");
const zinput = @import("zinput");
const utils = @import("utils.zig");

const LObject = union(enum) {
    Fixnum: i64,
    Boolean: bool,
    Symbol: []const u8,
};

const Parser = struct {
    input: []const u8,
    index: u8 = 0,

    fn isDone(self: *Parser) bool {
        return self.index >= self.input.len;
    }

    fn peek(self: *Parser) ?u8 {
        if (self.isDone()) {
            return null;
        }

        return self.input[self.index];
    }

    fn readCharacter(self: *Parser) ?u8 {
        if (self.isDone()) {
            return null;
        }

        const char = self.input[self.index];
        self.index += 1;
        return char;
    }

    fn unreadCharacter(self: *Parser) void {
        self.index = if (self.index <= 0) 0 else self.index - 1;
    }

    fn eatWhitespace(self: *Parser) void {
        const char = self.readCharacter() orelse return;

        if (utils.isWhitespace(char)) {
            self.eatWhitespace();
        } else {
            self.unreadCharacter();
        }
    }

    fn readFixnum(self: *Parser, isNegative: bool) !LObject {
        if (isNegative) _ = self.readCharacter();

        const startIndex = self.index;
        while (!self.isDone() and utils.isDigit(self.peek().?)) {
            _ = self.readCharacter();
        }
        const endIndex = self.index;

        const num = try std.fmt.parseInt(i64, self.input[startIndex..endIndex], 10);
        const fixnum = if (isNegative) -num else num;
        return LObject{ .Fixnum = fixnum };
    }

    fn readBoolean(self: *Parser) !LObject {
        _ = self.readCharacter();
        const nextChar = self.readCharacter() orelse return error.UnexpectedValue;
        const boolean = switch (nextChar) {
            't' => true,
            'f' => false,
            else => return error.UnexpectedValue,
        };

        return LObject{ .Boolean = boolean };
    }

    pub fn readSymbol(self: *Parser) !LObject {
        const startIndex = self.index;
        while (!self.isDone() and !utils.isDelimiter(self.peek().?)) {
            _ = self.readCharacter();
        }
        const endIndex = self.index;

        const symbol = self.input[startIndex..endIndex];
        return LObject{ .Symbol = symbol };
    }

    fn readSexp(self: *Parser) !LObject {
        self.eatWhitespace();
        const char = self.peek() orelse return error.UnexpectedEndOfContent;

        if (utils.isSymbolStartCharacter(char)) {
            const symbol = self.readSymbol();
            if (!self.isDone()) {
                return error.UnexpectedValue;
            }
            return symbol;
        } else if (utils.isDigit(char) or char == '~') {
            const isNegative = char == '~';
            const fixnum = self.readFixnum(isNegative);
            if (!self.isDone()) {
                return error.UnexpectedValue;
            }
            return fixnum;
        } else if (char == '#') {
            const boolean = self.readBoolean();
            if (!self.isDone()) {
                return error.UnexpectedValue;
            }
            return boolean;
        } else {
            return error.UnexpectedValue;
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
        defer allocator.free(string);

        var parser = Parser{ .input = string };
        const sexp = parser.readSexp() catch |err| {
            switch (err) {
                error.UnexpectedEndOfContent => std.debug.print("No value provided.\n", .{}),
                error.UnexpectedValue => std.debug.print("Unrecognized value.\n", .{}),
                error.Overflow => std.debug.print("Number is too large.\n", .{}),
                else => std.debug.print("Unexpected error.\n", .{}),
            }
            continue;
        };

        const printedSexp = printSexp(allocator, sexp) catch continue;
        defer allocator.free(printedSexp);

        std.debug.print("{s}\n", .{printedSexp});
    }
}

fn printSexp(allocator: *std.mem.Allocator, sexp: LObject) ![]const u8 {
    return switch (sexp) {
        .Fixnum => |num| try std.fmt.allocPrint(allocator, "{}", .{num}),
        .Boolean => |boolean| try std.fmt.allocPrint(allocator, "{}", .{boolean}),
        .Symbol => |symbol| try std.fmt.allocPrint(allocator, "{s}", .{symbol}),
    };
}
