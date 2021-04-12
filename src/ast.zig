const std = @import("std");
const LObject = @import("values.zig").LObject;
const Expression = @import("values.zig").Expression;
const DefExpression = @import("values.zig").DefExpression;
const isList = @import("utils.zig").isList;

const BuildError = error{UnexpectedValue} || std.mem.Allocator.Error;

pub fn buildAst(allocator: *std.mem.Allocator, sexp: *LObject) BuildError!*Expression {
    var expression = try allocator.create(Expression);
    errdefer allocator.destroy(expression);

    switch (sexp.*) {
        .Primitive => unreachable,
        .Fixnum, .Boolean, .Nil => {
            expression.* = .{ .Literal = sexp };
        },
        .Symbol => |origName| {
            var name = try allocator.dupe(u8, origName);
            expression.* = .{ .Variable = name };
        },
        .Pair => try buildAstFromPair(allocator, sexp, expression),
    }

    return expression;
}

fn buildAstFromPair(allocator: *std.mem.Allocator, sexp: *LObject, expression: *Expression) BuildError!void {
    const list = (try sexp.getListSlice(allocator)) orelse return error.UnexpectedValue;
    defer allocator.free(list);

    if (list.len == 0) return error.UnexpectedValue;

    const symbol = list[0].getValue(.Symbol) orelse return error.UnexpectedValue;

    if (list.len == 4 and std.mem.eql(u8, symbol, "if")) {
        const condition = try buildAst(allocator, list[1]);
        errdefer destroyAst(allocator, condition);

        const consequent = try buildAst(allocator, list[2]);
        errdefer destroyAst(allocator, consequent);

        const alternate = try buildAst(allocator, list[3]);

        expression.* = .{ .If = .{ condition, consequent, alternate } };
        return;
    }

    if (list.len == 3 and std.mem.eql(u8, symbol, "and")) {
        const condition1 = try buildAst(allocator, list[1]);
        errdefer destroyAst(allocator, condition1);

        const condition2 = try buildAst(allocator, list[2]);

        expression.* = .{ .And = .{ condition1, condition2 } };
        return;
    }

    if (list.len == 3 and std.mem.eql(u8, symbol, "or")) {
        const condition1 = try buildAst(allocator, list[1]);
        errdefer destroyAst(allocator, condition1);

        const condition2 = try buildAst(allocator, list[2]);

        expression.* = .{ .Or = .{ condition1, condition2 } };
        return;
    }

    if (list.len == 3 and std.mem.eql(u8, symbol, "val")) blk: {
        const origName = list[1].getValue(.Symbol) orelse break :blk;

        const name = try allocator.dupe(u8, origName);
        errdefer allocator.free(name);

        const expr = try buildAst(allocator, list[2]);
        errdefer destroyAst(allocator, expr);

        var defExpr = try allocator.create(DefExpression);
        defExpr.* = .{ .Val = .{ .Name = name, .Expression = expr } };

        expression.* = .{ .DefExpression = defExpr };
        return;
    }

    if (list.len == 3 and std.mem.eql(u8, symbol, "apply")) blk: {
        const function = list[1];
        const arguments = list[2];
        if (!isList(arguments.*)) break :blk;

        const functionExpr = try buildAst(allocator, function);
        errdefer destroyAst(allocator, functionExpr);
        const argumentsExpr = try buildAst(allocator, arguments);

        expression.* = .{ .Apply = .{ functionExpr, argumentsExpr } };
        break :blk;
    }

    const function = try buildAst(allocator, list[0]);
    errdefer destroyAst(allocator, function);

    const arguments = try allocator.alloc(*Expression, list.len - 1);
    errdefer allocator.free(arguments);

    for (list[1..]) |argument, i| {
        arguments[i] = buildAst(allocator, argument) catch |err| {
            // Clear previous nodes when we encounter an error.
            for (arguments[1 .. i - 1]) |arg| destroyAst(allocator, arg);
            return err;
        };
    }

    expression.* = .{ .Call = .{ .Function = function, .Arguments = arguments } };
}

/// Does not destroy any references to `LObject`.
pub fn destroyAst(allocator: *std.mem.Allocator, expression: *Expression) void {
    switch (expression.*) {
        .Literal => {},
        .Variable => |name| allocator.free(name),
        .If => |expressions| {
            destroyAst(allocator, expressions[0]);
            destroyAst(allocator, expressions[1]);
            destroyAst(allocator, expressions[2]);
        },
        .And => |expressions| {
            destroyAst(allocator, expressions[0]);
            destroyAst(allocator, expressions[1]);
        },
        .Or => |expressions| {
            destroyAst(allocator, expressions[0]);
            destroyAst(allocator, expressions[1]);
        },
        .Apply => |expressions| {
            destroyAst(allocator, expressions[0]);
            destroyAst(allocator, expressions[1]);
        },
        .Call => |call| {
            destroyAst(allocator, call.Function);
            for (call.Arguments) |argument| {
                destroyAst(allocator, argument);
            }
            allocator.free(call.Arguments);
        },
        .DefExpression => |defExpr| {
            destroyAst(allocator, defExpr.Expression);
            destroyAst(allocator, defExpr.Val.Expression);
            allocator.free(defExpr.Val.Name);
        },
    }

    allocator.destroy(expression);
}
