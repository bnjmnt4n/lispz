const std = @import("std");
const LObject = @import("values.zig").LObject;
const utils = @import("utils.zig");

// Note: recursive functions cannot have inferred error sets.
// See https://github.com/ziglang/zig/issues/2971.
pub const ParserError = error{
    UnexpectedValue,
    UnexpectedEndOfContent,
} || std.fmt.ParseIntError || std.mem.Allocator.Error;

pub const Parser = struct {
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
        node.* = .{ .Fixnum = fixnum };
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
        node.* = .{ .Boolean = boolean };
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
        node.* = .{ .Symbol = symbol };
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

            node.* = .{ .Pair = .{ car, cdr } };
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

    pub fn getValue(self: *Self) ParserError!LObject {
        const sexpPointer = try self.readSexp();

        self.eatWhitespace();
        if (!self.isDone()) {
            return error.UnexpectedValue;
        } else {
            return sexpPointer.*;
        }
    }
};
