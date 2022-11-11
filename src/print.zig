const std = @import("std");
const LObject = @import("values.zig").LObject;
const isList = @import("utils.zig").isList;

pub const PrinterError = error{UnexpectedValue} || std.fmt.AllocPrintError;

pub fn print(allocator: std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    return switch (sexp) {
        .Symbol => |symbol| try std.fmt.allocPrint(allocator, "{s}", .{symbol}),
        .Fixnum => |num| try std.fmt.allocPrint(allocator, "{}", .{num}),
        .Boolean => |boolean| try std.fmt.allocPrint(allocator, "{s}", .{if (boolean) "#t" else "#f"}),
        // TODO: figure out context and print () only if embedded within a list?
        .Nil => try std.fmt.allocPrint(allocator, "()", .{}),
        .Pair => {
            const content = if (isList(sexp))
                (try printList(allocator, sexp))
            else
                (try printPair(allocator, sexp));
            defer allocator.free(content);

            return try std.fmt.allocPrint(allocator, "({s})", .{content});
        },
        .Primitive => |primitive| try std.fmt.allocPrint(allocator, "#<primitive:{s}>", .{primitive.Name}),
    };
}

fn printPair(allocator: std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const pair = sexp.getValue(.Pair).?;

    const car = try print(allocator, pair[0].*);
    defer allocator.free(car);
    const cdr = try print(allocator, pair[1].*);
    defer allocator.free(cdr);

    return try std.fmt.allocPrint(allocator, "{s} . {s}", .{ car, cdr });
}

fn printList(allocator: std.mem.Allocator, sexp: LObject) PrinterError![]const u8 {
    const pair = sexp.getValue(.Pair).?;
    const car = try print(allocator, pair[0].*);
    defer allocator.free(car);

    const cdr = switch (pair[1].*) {
        .Nil => try std.fmt.allocPrint(allocator, "", .{}),
        .Pair => blk: {
            const cdr = try printList(allocator, pair[1].*);
            defer allocator.free(cdr);
            break :blk try std.fmt.allocPrint(allocator, " {s}", .{cdr});
        },
        else => unreachable,
    };
    defer allocator.free(cdr);

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ car, cdr });
}
