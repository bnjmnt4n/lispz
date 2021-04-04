const std = @import("std");
const LObject = @import("values.zig").LObject;
const Expression = @import("values.zig").Expression;
const DefExpression = @import("values.zig").DefExpression;
const isList = @import("utils.zig").isList;

const BuildError = error{UnexpectedValue} || std.mem.Allocator.Error;

pub fn buildAst(allocator: *std.mem.Allocator, sexp: *LObject) BuildError!*Expression {
    var expression = try allocator.create(Expression);

    switch (sexp.*) {
        .Primitive => unreachable,
        .Fixnum, .Boolean, .Nil => {
            expression.* = .{ .Literal = sexp };
        },
        .Symbol => |name| {
            expression.* = .{ .Variable = name };
        },
        .Pair => |pair| blk: {
            const list = (try sexp.getListSlice(allocator)) orelse return error.UnexpectedValue;

            if (list.len == 0) return error.UnexpectedValue;

            const symbol = list[0].getValue(.Symbol) orelse return error.UnexpectedValue;

            if (list.len == 4 and std.mem.eql(u8, symbol, "if")) {
                expression.* = .{
                    .If = .{
                        try buildAst(allocator, list[1]),
                        try buildAst(allocator, list[2]),
                        try buildAst(allocator, list[3]),
                    },
                };
                break :blk;
            }

            if (list.len == 3 and std.mem.eql(u8, symbol, "and")) {
                expression.* = .{
                    .And = .{
                        try buildAst(allocator, list[1]),
                        try buildAst(allocator, list[2]),
                    },
                };
                break :blk;
            }

            if (list.len == 3 and std.mem.eql(u8, symbol, "or")) {
                expression.* = .{
                    .Or = .{
                        try buildAst(allocator, list[1]),
                        try buildAst(allocator, list[2]),
                    },
                };
                break :blk;
            }

            if (list.len == 3 and std.mem.eql(u8, symbol, "val")) {
                const name = list[1].getValue(.Symbol) orelse break :blk;

                var defExpr = try allocator.create(DefExpression);
                defExpr.* = .{
                    .Val = .{
                        .Name = name,
                        .Expression = try buildAst(allocator, list[2]),
                    },
                };

                expression.* = .{ .DefExpression = defExpr };
                break :blk;
            }

            if (list.len == 3 and std.mem.eql(u8, symbol, "apply")) {
                const function = list[1];
                const arguments = list[2];
                if (!isList(arguments.*)) break :blk;

                expression.* = .{
                    .Apply = .{
                        try buildAst(allocator, function),
                        try buildAst(allocator, arguments),
                    },
                };
                break :blk;
            }

            const function = try buildAst(allocator, list[0]);
            const arguments = try allocator.alloc(*Expression, list.len - 1);
            for (list[1..]) |argument, i| {
                arguments[i] = try buildAst(allocator, argument);
            }

            expression.* = .{
                .Call = .{
                    .Function = function,
                    .Arguments = arguments,
                },
            };
            break :blk;
        },
    }

    return expression;
}
