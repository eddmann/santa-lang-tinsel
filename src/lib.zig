const std = @import("std");
pub const lexer = @import("lexer.zig");
pub const token = @import("token.zig");
pub const parser = @import("parser.zig");
pub const ast = @import("ast.zig");
pub const doc = @import("doc.zig");
pub const builder = @import("builder.zig");
pub const printer = @import("printer.zig");

const Lexer = lexer.Lexer;
const Parser = parser.Parser;
const DocBuilder = doc.DocBuilder;

pub const FormatError = error{
    ParseError,
    OutOfMemory,
};

/// Formats santa-lang source code according to the opinionated style guide.
///
/// This function parses the source code, transforms it into an intermediate
/// document representation, and renders it with intelligent line-breaking.
///
/// Returns an owned slice that the caller must free.
pub fn format(allocator: std.mem.Allocator, source: []const u8) FormatError![]const u8 {
    var lex = Lexer.init(source);
    var parse = Parser.init(allocator, &lex);

    var program = parse.parse() catch return FormatError.ParseError;
    defer program.deinit(allocator);

    var docBuilder = DocBuilder.init(allocator);
    defer docBuilder.deinit();

    const docTree = builder.buildProgram(&docBuilder, &program) catch return FormatError.OutOfMemory;

    return printer.print(allocator, docTree) catch return FormatError.OutOfMemory;
}

/// Checks if source code is already formatted according to the style guide.
///
/// This is equivalent to `std.mem.eql(u8, format(source), source)` but
/// communicates intent clearly. Useful for CI checks or editor integrations
/// that want to warn about unformatted code without actually reformatting.
pub fn isFormatted(allocator: std.mem.Allocator, source: []const u8) FormatError!bool {
    const formatted = try format(allocator, source);
    defer allocator.free(formatted);
    return std.mem.eql(u8, formatted, source);
}

// Re-export key types for external use
pub const Token = token.Token;
pub const TokenKind = token.TokenKind;
pub const Program = ast.Program;
pub const Statement = ast.Statement;
pub const Expression = ast.Expression;

// Tests
const testing = std.testing;

test "format: integer" {
    const result = try format(testing.allocator, "42");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("42\n", result);
}

test "format: infix adds spaces" {
    const result = try format(testing.allocator, "1+2");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("1 + 2\n", result);
}

test "format: list" {
    const result = try format(testing.allocator, "[1,2,3]");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("[1, 2, 3]\n", result);
}

test "format: lambda" {
    const result = try format(testing.allocator, "|x|x+1");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("|x| x + 1\n", result);
}

test "format: let" {
    const result = try format(testing.allocator, "let x=1");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("let x = 1\n", result);
}

test "format: idempotent" {
    const source = "1 + 2\n";
    const result = try format(testing.allocator, source);
    defer testing.allocator.free(result);

    const result2 = try format(testing.allocator, result);
    defer testing.allocator.free(result2);

    try testing.expectEqualStrings(result, result2);
}

test "isFormatted: returns true for formatted" {
    const result = try isFormatted(testing.allocator, "1 + 2\n");
    try testing.expect(result);
}

test "isFormatted: returns false for unformatted" {
    const result = try isFormatted(testing.allocator, "1+2");
    try testing.expect(!result);
}

test "format: string" {
    const result = try format(testing.allocator, "\"hello\"");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("\"hello\"\n", result);
}

test "format: boolean true" {
    const result = try format(testing.allocator, "true");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("true\n", result);
}

test "format: boolean false" {
    const result = try format(testing.allocator, "false");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("false\n", result);
}

test "format: nil" {
    const result = try format(testing.allocator, "nil");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("nil\n", result);
}

test "format: prefix bang" {
    const result = try format(testing.allocator, "!true");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("!true\n", result);
}

test "format: prefix minus" {
    const result = try format(testing.allocator, "-42");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("-42\n", result);
}

test "format: range exclusive" {
    const result = try format(testing.allocator, "1..10");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("1..10\n", result);
}

test "format: range inclusive" {
    const result = try format(testing.allocator, "1..=10");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("1..=10\n", result);
}

test "format: empty list" {
    const result = try format(testing.allocator, "[]");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("[]\n", result);
}

test "format: empty set" {
    const result = try format(testing.allocator, "{}");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("{}\n", result);
}

test "format: empty dict" {
    const result = try format(testing.allocator, "#{}");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("#{}\n", result);
}

test "format: call no args" {
    const result = try format(testing.allocator, "f()");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("f()\n", result);
}

test "format: call with args" {
    const result = try format(testing.allocator, "f(1,2,3)");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("f(1, 2, 3)\n", result);
}

test "format: index" {
    const result = try format(testing.allocator, "arr[0]");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("arr[0]\n", result);
}

test "format: pipe two elements inline" {
    const result = try format(testing.allocator, "[1, 2] |> sum");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("[1, 2] |> sum\n", result);
}

test "format: if else inline" {
    const result = try format(testing.allocator, "if x { 1 } else { 2 }");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("if x { 1 } else { 2 }\n", result);
}

test {
    // Run all tests from imported modules
    _ = lexer;
    _ = parser;
    _ = doc;
    _ = printer;
}
