const std = @import("std");
const zinput = @import("zinput");
const LObject = @import("values.zig").LObject;
const Parser = @import("parser.zig").Parser;
const print = @import("print.zig").print;
const buildAst = @import("ast.zig").buildAst;
const eval = @import("evaluate.zig").eval;
const utils = @import("utils.zig");
const constructEnvironment = @import("primitives.zig").constructEnvironment;

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var environmentValue: LObject = LObject.Nil;
    var environment = &environmentValue;
    environment = try constructEnvironment(allocator, environment);

    // Read-Eval-Print-Loop
    while (true) {
        const string = zinput.askString(allocator, "> ", 128) catch |err| switch (err) {
            error.EndOfStream => {
                std.debug.print("^D\n", .{});
                return;
            },
            else => {
                std.debug.print("Unexpected error occured.\n", .{});
                return err;
            },
        };

        var parser = Parser.init(allocator, string);
        var sexp = parser.getValue() catch |err| {
            switch (err) {
                error.UnexpectedEndOfContent => std.debug.print("No value provided.\n", .{}),
                error.UnexpectedValue => std.debug.print("Unrecognized value.\n", .{}),
                error.Overflow => std.debug.print("Number is too large.\n", .{}),
                else => std.debug.print("Unexpected error.\n", .{}),
            }
            continue;
        };

        const ast = try buildAst(allocator, &sexp);

        const evalResult = eval(allocator, ast, environment) catch |err| switch (err) {
            error.NotFound => {
                std.debug.print("Couldn't find value.\n", .{});
                continue;
            },
            else => {
                std.debug.print("Error evaluating value.\n", .{});
                continue;
            },
        };

        const evaluatedValue = evalResult[0];
        environment = evalResult[1];

        const printedValue = print(allocator, evaluatedValue.*) catch |err| {
            std.debug.print("Error printing value.\n", .{});
            continue;
        };

        std.debug.print("{s}\n", .{printedValue});
    }
}
