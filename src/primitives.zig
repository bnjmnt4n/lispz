const std = @import("std");
const LObject = @import("values.zig").LObject;
const Primitive = @import("values.zig").Primitive;
const bind = @import("evaluate.zig").bind;
const EvaluationError = @import("evaluate.zig").EvaluationError;

fn primitiveList(allocator: *std.mem.Allocator, list: []*LObject, environment: *LObject) EvaluationError!?[2]*LObject {
    var i = list.len;

    var node = try allocator.create(LObject);
    node.* = LObject.Nil;

    while (i > 0) : (i -= 1) {
        var car = list[i - 1];

        var pair = try allocator.create(LObject);
        pair.* = .{ .Pair = .{ car, node } };

        node = pair;
    }

    return [2]*LObject{ node, environment };
}

fn primitivePair(allocator: *std.mem.Allocator, list: []*LObject, environment: *LObject) EvaluationError!?[2]*LObject {
    if (list.len != 2) return null;
    const car = list[0];
    const cdr = list[1];

    var node = try allocator.create(LObject);
    node.* = .{ .Pair = .{ car, cdr } };
    return [2]*LObject{ node, environment };
}

fn primitiveAdd(allocator: *std.mem.Allocator, list: []*LObject, environment: *LObject) EvaluationError!?[2]*LObject {
    if (list.len != 2) return null;
    const a = list[0].getValue(.Fixnum) orelse return null;
    const b = list[1].getValue(.Fixnum) orelse return null;

    const fixnum = a + b;

    var node = try allocator.create(LObject);
    node.* = .{ .Fixnum = fixnum };
    return [2]*LObject{ node, environment };
}

const Primitives = &[_]Primitive{
    .{ .Name = "list", .Function = primitiveList },
    .{ .Name = "pair", .Function = primitivePair },
    .{ .Name = "+", .Function = primitiveAdd },
};

pub fn constructEnvironment(allocator: *std.mem.Allocator, environment: *LObject) EvaluationError!*LObject {
    var env = environment;

    for (Primitives) |primitive| {
        var lobject = try allocator.create(LObject);
        lobject.* = .{ .Primitive = primitive };
        env = try bind(allocator, primitive.Name, lobject, env);
    }

    return env;
}
