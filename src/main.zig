const std = @import("std");
const zinput = @import("zinput");

const LObject = union(enum) {
    Fixnum: i64,
};

const Parser = struct {
    input: []u8,
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

        if (isWhitespace(char)) {
            self.eatWhitespace();
        } else {
            self.unreadCharacter();
        }
    }

    fn readFixnum(self: *Parser) !LObject {
        const startIndex = self.index;
        while (!self.isDone() and isDigit(self.peek().?)) {
            _ = self.readCharacter();
        }
        const endIndex = self.index;

        const fixnum = try std.fmt.parseInt(i64, self.input[startIndex..endIndex], 10);
        return LObject{ .Fixnum = fixnum };
    }

    fn readSexp(self: *Parser) !LObject {
        self.eatWhitespace();
        const char = self.peek() orelse return error.UnexpectedEndOfContent;

        if (isDigit(char)) {
            const fixnum = self.readFixnum();
            if (!self.isDone()) {
                return error.UnexpectedValue;
            }
            return fixnum;
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

        printSexp(sexp);
    }
}

fn printSexp(sexp: LObject) void {
    switch (sexp) {
        .Fixnum => |num| {
            std.debug.print("{}\n", .{num});
        },
        // else => {
        //     std.debug.print("", .{});
        // },
    }
}

fn isWhitespace(char: u8) bool {
    return switch (char) {
        ' ', '\t', '\n' => true,
        else => false,
    };
}

fn isDigit(char: u8) bool {
    return switch (char) {
        '0'...'9' => true,
        else => false,
    };
}
