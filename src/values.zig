const std = @import("std");
const EvaluationError = @import("evaluate.zig").EvaluationError;

pub const LObject = union(enum) {
    Fixnum: i64,
    Boolean: bool,
    Symbol: []const u8,
    Nil,
    // TODO: figure out the differences between *const LObject and *LObject.
    Pair: [2]*LObject,

    pub fn getValue(self: LObject, comptime tag: std.meta.Tag(LObject)) ?std.meta.TagPayload(LObject, tag) {
        return switch (self) {
            tag => @field(self, @tagName(tag)),
            else => null,
        };
    }

    pub fn getListSlice(self: LObject, allocator: *std.mem.Allocator) !?[]*LObject {
        const length = getListLength(self) orelse return null;

        var slice = try allocator.alloc(*LObject, length);
        var count: u8 = 0;
        var list = self;

        while (list != .Nil) : ({
            list = list.Pair[1].*;
            count += 1;
        }) {
            slice[count] = list.Pair[0];
        }

        return slice;
    }
};

pub const Primitive = struct {
    Name: []const u8,
    Function: fn (allocator: *std.mem.Allocator, list: []*LObject, environment: *LObject) EvaluationError!?[2]*LObject,
};

fn getListLength(sexp: LObject) ?u8 {
    return switch (sexp) {
        .Nil => 0,
        .Pair => |nextPair| {
            const nextCount = getListLength(nextPair[1].*) orelse return null;
            return nextCount + 1;
        },
        else => null,
    };
}
