const std = @import("std");
const LObject = @import("values.zig").LObject;

pub const PrinterError = error{UnexpectedValue} || std.fmt.AllocPrintError;

pub fn printSexp(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    return switch (sexp) {
        .Symbol => |symbol| try std.fmt.allocPrint(allocator, "{s}", .{symbol}),
        .Fixnum => |num| try std.fmt.allocPrint(allocator, "{}", .{num}),
        .Boolean => |boolean| if (boolean) "#t" else "#f",
        // TODO: figure out context and print () only if embedded within a list?
        .Nil => "()",
        .Pair => {
            const content = if (isList(sexp))
                (try printList(allocator, sexp))
            else
                (try printPair(allocator, sexp));
            return try std.fmt.allocPrint(allocator, "({s})", .{content});
        },
        .Primitive => |primitive| try std.fmt.allocPrint(allocator, "#<primitive:{s}>", .{primitive.Name}),
    };
}

fn printPair(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const pair = sexp.getValue(.Pair) orelse unreachable;

    return try std.fmt.allocPrint(allocator, "{s} . {s}", .{
        try printSexp(allocator, pair[0].*),
        try printSexp(allocator, pair[1].*),
    });
}

fn printList(allocator: *std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const pair = sexp.getValue(.Pair) orelse unreachable;
    const car = try printSexp(allocator, pair[0].*);

    const cdr = switch (pair[1].*) {
        .Nil => "",
        .Pair => try std.fmt.allocPrint(allocator, " {s}", .{
            try printList(allocator, pair[1].*),
        }),
        else => unreachable,
    };

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ car, cdr });
}

fn isList(sexp: LObject) bool {
    return switch (sexp) {
        .Nil => true,
        .Pair => |nextPair| isList(nextPair[1].*),
        else => false,
    };
}
