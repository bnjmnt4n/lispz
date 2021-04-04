const std = @import("std");
const zinput = @import("zinput");
const LObject = @import("values.zig").LObject;
const Parser = @import("parser.zig");
const print = @import("print.zig").print;
const buildAst = @import("ast.zig").buildAst;
const eval = @import("evaluate.zig").eval;
const utils = @import("utils.zig");
const constructEnvironment = @import("environment.zig").constructEnvironment;

pub fn main() anyerror!void {
    // Use an arena allocator for the REPL, so we don't have to care about
    // deallocation.
    // TODO: ensure that the rest of the library allocates and deallocates properly.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) std.debug.print("Memory leak occured.\n", .{});
    }

    var arena = std.heap.ArenaAllocator.init(&gpa.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var environment = constructEnvironment(allocator) catch |err| {
        std.debug.print("Unable to construct environment.\n", .{});
        return err;
    };

    // Read-Eval-Print-Loop
    while (true) {
        const string = zinput.askString(allocator, "> ", 128) catch |err| switch (err) {
            error.EndOfStream => {
                std.debug.print("^D\n", .{});
                return;
            },
            else => {
                std.debug.print("Unexpected error occured while accepting input.\n", .{});
                return err;
            },
        };

        var parser = Parser.init(allocator, string);
        var sexp = parser.getValue() catch |err| {
            switch (err) {
                error.UnexpectedEndOfContent => std.debug.print("Incomplete expression provided.\n", .{}),
                error.UnexpectedValue => std.debug.print("Unrecognized content found.\n", .{}),
                error.Overflow => std.debug.print("Number is too large.\n", .{}),
                else => {
                    std.debug.print("Unexpected error occurred while parsing expression.\n", .{});
                    return err;
                },
            }
            continue;
        };

        const ast = buildAst(allocator, &sexp) catch |err| switch (err) {
            error.UnexpectedValue => {
                std.debug.print("Unexpected value found while constructing AST.\n", .{});
                continue;
            },
            else => {
                std.debug.print("Unexpected error occurred while constructing AST.\n", .{});
                return err;
            },
        };

        const evalResult = eval(allocator, ast, environment) catch |err| switch (err) {
            error.NotFound => {
                std.debug.print("Couldn't find value in the environment.\n", .{});
                continue;
            },
            error.UnexpectedIfCondition => {
                std.debug.print("Expected a boolean for if-expression condition.\n", .{});
                continue;
            },
            error.UnexpectedValue => {
                std.debug.print("Unexpected value.\n", .{});
                continue;
            },
            else => {
                std.debug.print("Unexpected error occurred while evaluating expression.\n", .{});
                return err;
            },
        };

        const evaluatedValue = evalResult[0];
        environment = evalResult[1];

        const printedValue = print(allocator, evaluatedValue.*) catch |err| switch (err) {
            error.UnexpectedValue => {
                std.debug.print("Unexpected value found while printing expression.\n", .{});
                continue;
            },
            else => {
                std.debug.print("Unexpected error occurred while printing expression.\n", .{});
                return err;
            },
        };

        std.debug.print("{s}\n", .{printedValue});
    }
}
