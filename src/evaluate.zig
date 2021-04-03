const std = @import("std");
const LObject = @import("values.zig").LObject;
const Expression = @import("values.zig").Expression;
const executePrimitives = @import("primitives.zig").executePrimitives;

pub const EvaluationError = error{
    NotFound,
    UnexpectedIfCondition,
} || std.mem.Allocator.Error;

pub fn eval(allocator: *std.mem.Allocator, sexp: *Expression, environment: *LObject) EvaluationError![2]*LObject {
    return switch (sexp.*) {
        .Nil => .{ sexp, environment },
        .Fixnum => .{ sexp, environment },
        .Boolean => .{ sexp, environment },
        .Symbol => |name| .{ try lookup(name, environment), environment },
        .Pair => |pair| blk: {
            const defaultExpr = [2]*LObject{ sexp, environment };

            const list = (try sexp.getListSlice(allocator)) orelse break :blk defaultExpr;
            if (list.len == 0) break :blk defaultExpr;

            const symbol = list[0].getValue(.Symbol) orelse break :blk defaultExpr;

            if (list.len == 1 and std.mem.eql(u8, symbol, "env")) {
                const nextPair = pair[1].getValue(.Nil) orelse break :blk defaultExpr;
                break :blk [2]*LObject{ environment, environment };
            }

            if (list.len == 3 and std.mem.eql(u8, symbol, "val")) {
                const variableName = list[1].getValue(.Symbol) orelse break :blk defaultExpr;
                const variableValue = list[2];

                var result = try eval(allocator, variableValue, environment);
                const evaluatedVariableValue = result[0];
                const newEnvironment = result[1];

                const newEnvironment2 = try bind(allocator, variableName, variableValue, newEnvironment);

                break :blk [2]*LObject{ evaluatedVariableValue, newEnvironment2 };
            }

            if (list.len == 4 and std.mem.eql(u8, symbol, "if")) {
                const condition = list[1];
                const consequent = list[2];
                const alternate = list[3];

                var result = try eval(allocator, condition, environment);
                const conditionValue = result[0].getValue(.Boolean) orelse return error.UnexpectedIfCondition;
                switch (conditionValue) {
                    true => break :blk [2]*LObject{ consequent, environment },
                    false => break :blk [2]*LObject{ alternate, environment },
                }
            }

            return executePrimitives(allocator, symbol, list[1..], environment);
        },
        // Primitives cannot be evaluated.
        .Primitive => unreachable,
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
