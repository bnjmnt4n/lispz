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
            errdefer result.destroy(allocator);
            var name = try allocator.dupe(u8, value.Name);
            errdefer allocator.free(name);
            const newEnvironment = try bind(allocator, name, result, environment);

            break :blk .{ result, newEnvironment };
        },
        // TODO: figure out why the blog added an Expression type to DefExpression
        .Expression => |expression| blk: {
            const result = try evalExpression(allocator, expression, environment);
            break :blk .{ result, environment };
        },
    };
}

fn duplicateObject(allocator: *std.mem.Allocator, object: *LObject) std.mem.Allocator.Error!*LObject {
    var node = try allocator.create(LObject);
    errdefer allocator.destroy(node);

    switch (object.*) {
        .Boolean => |boolean| node.* = .{ .Boolean = boolean },
        .Fixnum => |num| node.* = .{ .Fixnum = num },
        .Nil => node.* = LObject.Nil,
        .Symbol => |origSymbol| {
            var symbol = try allocator.dupe(u8, origSymbol);
            node.* = .{ .Symbol = symbol };
        },
        .Pair => |pair| {
            const car = try duplicateObject(allocator, pair[0]);
            errdefer car.destroy(allocator);
            const cdr = try duplicateObject(allocator, pair[0]);
            node.* = .{ .Pair = .{ car, cdr } };
        },
        .Primitive => |primitive| node.* = .{ .Primitive = primitive },
    }

    return node;
}

pub fn evalExpression(allocator: *std.mem.Allocator, expression: *Expression, environment: *LObject) EvaluationError!*LObject {
    return switch (expression.*) {
        .Literal => |literal| try duplicateObject(allocator, literal),
        .Variable => |name| try duplicateObject(allocator, try lookup(name, environment)),
        .If => |expressions| blk: {
            const condition = try evalExpression(allocator, expressions[0], environment);
            defer condition.destroy(allocator);
            const result = condition.getValue(.Boolean) orelse return error.UnexpectedIfCondition;

            break :blk try evalExpression(allocator, if (result) expressions[1] else expressions[2], environment);
        },
        .And => |expressions| blk: {
            const expr1 = try evalExpression(allocator, expressions[0], environment);
            defer expr1.destroy(allocator);
            const expr2 = try evalExpression(allocator, expressions[1], environment);
            defer expr2.destroy(allocator);
            const result1 = expr1.getValue(.Boolean) orelse return error.UnexpectedValue;
            const result2 = expr2.getValue(.Boolean) orelse return error.UnexpectedValue;

            var node = try allocator.create(LObject);
            node.* = .{ .Boolean = result1 and result2 };
            break :blk node;
        },
        .Or => |expressions| blk: {
            const expr1 = try evalExpression(allocator, expressions[0], environment);
            defer expr1.destroy(allocator);
            const expr2 = try evalExpression(allocator, expressions[1], environment);
            defer expr2.destroy(allocator);
            const result1 = expr1.getValue(.Boolean) orelse return error.UnexpectedValue;
            const result2 = expr2.getValue(.Boolean) orelse return error.UnexpectedValue;

            var node = try allocator.create(LObject);
            node.* = .{ .Boolean = result1 or result2 };
            break :blk node;
        },
        .Apply => |expressions| blk: {
            const function = try evalExpression(allocator, expressions[0], environment);
            defer function.destroy(allocator);
            const argumentsList = try evalExpression(allocator, expressions[1], environment);
            defer argumentsList.destroy(allocator);
            // TODO: figure out error type.
            const argumentsSlice = (try argumentsList.getListSlice(allocator)) orelse return error.UnexpectedValue;
            defer allocator.free(argumentsSlice);

            break :blk evalApplication(allocator, function, argumentsSlice, environment);
        },
        .Call => |call| blk: {
            const arguments = call.Arguments;
            if (call.Function.* == Expression.Variable and std.mem.eql(u8, call.Function.Variable, "env") and arguments.len == 0) {
                break :blk environment;
            }
            const function = try evalExpression(allocator, call.Function, environment);
            defer function.destroy(allocator);

            const evaluatedArguments = try allocator.alloc(*LObject, arguments.len);
            for (arguments) |argument, i| {
                evaluatedArguments[i] = try evalExpression(allocator, argument, environment);
            }

            break :blk evalApplication(allocator, function, evaluatedArguments, environment);
        },
        else => unreachable,
    };
}

pub fn evalApplication(allocator: *std.mem.Allocator, function: *LObject, arguments: []*LObject, environment: *LObject) EvaluationError!*LObject {
    return switch (function.*) {
        .Primitive => |primitive| (try primitive.Function(allocator, arguments, environment)).?[0],
        else => error.UnexpectedValue,
    };
}

pub fn bind(allocator: *std.mem.Allocator, name: []const u8, value: *LObject, environment: *LObject) !*LObject {
    var symbol = try allocator.create(LObject);
    errdefer allocator.destroy(symbol);
    symbol.* = .{ .Symbol = name };

    var nameValuePair = try allocator.create(LObject);
    errdefer allocator.destroy(nameValuePair);
    nameValuePair.* = .{ .Pair = .{ symbol, value } };

    var newEnvironment = try allocator.create(LObject);
    newEnvironment.* = .{ .Pair = .{ nameValuePair, environment } };
    return newEnvironment;
}

fn lookup(name: []const u8, environment: *LObject) !*LObject {
    switch (environment.*) {
        .Nil => return error.NotFound,
        .Pair => |pair| {
            const nameValuePair = pair[0].getValue(.Pair).?;
            const nameSymbol = nameValuePair[0].getValue(.Symbol).?;

            if (std.mem.eql(u8, name, nameSymbol)) return nameValuePair[1];
            return lookup(name, pair[1]);
        },
        else => unreachable,
    }
}
