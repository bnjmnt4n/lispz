const std = @import("std");
const expect = std.testing.expect;
const LObject = @import("values.zig").LObject;
const Parser = @import("parser.zig");
const buildAst = @import("ast.zig").buildAst;
const destroyAst = @import("ast.zig").destroyAst;
const eval = @import("evaluate.zig").eval;
const print = @import("print.zig").print;
const constructEnvironment = @import("environment.zig").constructEnvironment;

// TODO: figure out memory leaks.
fn matches(allocator: std.mem.Allocator, input: []const u8, expected: []const u8) !void {
    var parser = Parser.init(allocator, input);
    var sexp = try parser.getValue();
    defer sexp.destroy(allocator);

    const ast = try buildAst(allocator, sexp);
    defer destroyAst(allocator, ast);

    const evalResult = try eval(allocator, ast, try constructEnvironment(allocator));
    const evaluatedSexp = evalResult[0];
    defer evaluatedSexp.destroy(allocator);
    const environment = evalResult[1];
    defer environment.destroy(allocator);

    const printedValue = try print(allocator, evalResult[0].*);
    defer allocator.free(printedValue);

    try expect(std.mem.eql(u8, printedValue, expected));
}

test "basic evaluation" {
    const allocator = std.testing.allocator;

    try matches(allocator, "(+ 1 2)", "3");
    try matches(allocator, "(if #t 1 2)", "1");
    try matches(allocator, "(if #f 1 2)", "2");
    try matches(allocator, "(pair 1 2)", "(1 . 2)");
    try matches(allocator, "(list 1 2 3)", "(1 2 3)");
}
