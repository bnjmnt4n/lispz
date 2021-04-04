const std = @import("std");
const LObject = @import("values.zig").LObject;
const Expression = @import("values.zig").Expression;
const DefExpression = @import("values.zig").DefExpression;

pub const EvaluationError = error{
    NotFound,
    UnexpectedIfCondition,
    UnexpectedValue,
} || std.mem.Allocator.Error;

pub fn eval(allocator: *std.mem.Allocator, expression: *Expression, environment: *LObject) EvaluationError![2]*LObject {
    return switch (expression.*) {
        // Only DefExpressions modify the environment.
        .DefExpression => |defExpr| evalDefExpression(allocator, defExpr, environment),
        else => blk: {
            const result = try evalExpression(allocator, expression, environment);
            break :blk .{ result, environment };
        },
    };
}

fn evalDefExpression(allocator: *std.mem.Allocator, defExpr: *DefExpression, environment: *LObject) EvaluationError![2]*LObject {
    return switch (defExpr.*) {
        .Val => |value| blk: {
            const result = try evalExpression(allocator, value.Expression, environment);
            const newEnvironment = try bind(allocator, value.Name, result, environment);

            break :blk .{ result, newEnvironment };
        },
        // TODO: figure out why the blog added an Expression type to DefExpression
        .Expression => |expression| blk: {
            const result = try evalExpression(allocator, expression, environment);
            break :blk .{ result, environment };
        },
    };
}

pub fn evalExpression(allocator: *std.mem.Allocator, expression: *Expression, environment: *LObject) EvaluationError!*LObject {
    return switch (expression.*) {
        .Literal => |literal| literal,
        .Variable => |name| try lookup(name, environment),
        .If => |expressions| blk: {
            const condition = try evalExpression(allocator, expressions[0], environment);
            const result = condition.getValue(.Boolean) orelse return error.UnexpectedIfCondition;

            break :blk try evalExpression(allocator, if (result) expressions[1] else expressions[2], environment);
        },
        .And => |expressions| blk: {
            const expr1 = try evalExpression(allocator, expressions[0], environment);
            const expr2 = try evalExpression(allocator, expressions[1], environment);
            const result1 = expr1.getValue(.Boolean) orelse return error.UnexpectedValue;
            const result2 = expr2.getValue(.Boolean) orelse return error.UnexpectedValue;

            var node = try allocator.create(LObject);
            node.* = .{ .Boolean = result1 and result2 };
            break :blk node;
        },
        .Or => |expressions| blk: {
            const expr1 = try evalExpression(allocator, expressions[0], environment);
            const expr2 = try evalExpression(allocator, expressions[1], environment);
            const result1 = expr1.getValue(.Boolean) orelse return error.UnexpectedValue;
            const result2 = expr2.getValue(.Boolean) orelse return error.UnexpectedValue;

            var node = try allocator.create(LObject);
            node.* = .{ .Boolean = result1 or result2 };
            break :blk node;
        },
        // TODO
        // .Apply => |expressions| blk: {
        //     break :blk;
        // },
        // .Call => |call| blk: {
        //     break :blk;
        // },
        else => unreachable,
    };
}

fn bind(allocator: *std.mem.Allocator, name: []const u8, value: *LObject, environment: *LObject) !*LObject {
    var symbol = try allocator.create(LObject);
    symbol.* = .{ .Symbol = name };

    var nameValuePair = try allocator.create(LObject);
    nameValuePair.* = .{ .Pair = .{ symbol, value } };

    var newEnvironment = try allocator.create(LObject);
    newEnvironment.* = .{ .Pair = .{ nameValuePair, environment } };
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
