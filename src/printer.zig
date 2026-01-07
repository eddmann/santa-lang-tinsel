const std = @import("std");
const doc = @import("doc.zig");
const Doc = doc.Doc;

/// Maximum line width for formatted output.
/// Lines exceeding this width will be broken into multiple lines when possible.
pub const LINE_WIDTH: usize = 100;

/// Pre-allocated indentation buffer to avoid repeated string allocations.
/// Contains 100 spaces, sufficient for most indentation levels.
const INDENT_BUFFER: *const [100]u8 = "                                                                                                    ";

const Mode = enum {
    flat,
    @"break",
};

/// Command for the printer's work stack.
const Cmd = struct {
    indent: usize,
    mode: Mode,
    doc: *const Doc,
};

/// Returns a string of spaces for the given indentation level.
fn indentStr(indent: usize) []const u8 {
    const clamped = @min(indent, INDENT_BUFFER.len);
    return INDENT_BUFFER[0..clamped];
}

/// Renders a Doc to a formatted string with intelligent line-breaking.
pub fn print(allocator: std.mem.Allocator, d: *const Doc) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var column: usize = 0;
    var cmds: std.ArrayList(Cmd) = .empty;
    defer cmds.deinit(allocator);

    try cmds.append(allocator, .{ .indent = 0, .mode = .@"break", .doc = d });

    while (cmds.pop()) |cmd| {
        switch (cmd.doc.*) {
            .nil => {},

            .text => |s| {
                try output.appendSlice(allocator, s);
                column += s.len;
            },

            .line => {
                if (cmd.mode == .flat) {
                    try output.append(allocator, ' ');
                    column += 1;
                } else {
                    try output.append(allocator, '\n');
                    try output.appendSlice(allocator, indentStr(cmd.indent));
                    column = cmd.indent;
                }
            },

            .hard_line => {
                try output.append(allocator, '\n');
                try output.appendSlice(allocator, indentStr(cmd.indent));
                column = cmd.indent;
            },

            .blank_line => {
                try output.append(allocator, '\n');
                column = 0;
            },

            .concat => |docs| {
                // Push in reverse order so we process left-to-right
                var i = docs.len;
                while (i > 0) {
                    i -= 1;
                    try cmds.append(allocator, .{ .indent = cmd.indent, .mode = cmd.mode, .doc = &docs[i] });
                }
            },

            .nest => |n| {
                try cmds.append(allocator, .{ .indent = cmd.indent + n.indent, .mode = cmd.mode, .doc = n.doc });
            },

            .group => |inner| {
                if (cmd.mode == .flat) {
                    try cmds.append(allocator, .{ .indent = cmd.indent, .mode = .flat, .doc = inner });
                } else {
                    const remaining = if (LINE_WIDTH > column) LINE_WIDTH - column else 0;
                    const flat_width = measureFlat(inner, remaining);
                    if (flat_width != null) {
                        try cmds.append(allocator, .{ .indent = cmd.indent, .mode = .flat, .doc = inner });
                    } else {
                        try cmds.append(allocator, .{ .indent = cmd.indent, .mode = .@"break", .doc = inner });
                    }
                }
            },

            .if_break => |ib| {
                if (cmd.mode == .flat) {
                    try cmds.append(allocator, .{ .indent = cmd.indent, .mode = cmd.mode, .doc = ib.flat });
                } else {
                    try cmds.append(allocator, .{ .indent = cmd.indent, .mode = cmd.mode, .doc = ib.broken });
                }
            },
        }
    }

    return output.toOwnedSlice(allocator);
}

/// Measures the width of a document if printed in flat mode.
/// Returns null if the document cannot be printed flat (contains hard lines)
/// or exceeds the remaining width.
fn measureFlat(d: *const Doc, remaining: usize) ?usize {
    var width: usize = 0;

    // Use a simple iterative approach with a stack
    var stack: [256]*const Doc = undefined;
    var stack_len: usize = 1;
    stack[0] = d;

    while (stack_len > 0) {
        if (width > remaining) {
            return null;
        }

        stack_len -= 1;
        const current = stack[stack_len];

        switch (current.*) {
            .nil => {},
            .text => |s| width += s.len,
            .line => width += 1, // Space in flat mode
            .hard_line, .blank_line => return null, // Can't go flat
            .concat => |docs| {
                // Push in reverse order
                var i = docs.len;
                while (i > 0) {
                    i -= 1;
                    if (stack_len >= stack.len) return null; // Stack overflow - treat as can't go flat
                    stack[stack_len] = &docs[i];
                    stack_len += 1;
                }
            },
            .nest => |n| {
                if (stack_len >= stack.len) return null;
                stack[stack_len] = n.doc;
                stack_len += 1;
            },
            .group => |inner| {
                if (stack_len >= stack.len) return null;
                stack[stack_len] = inner;
                stack_len += 1;
            },
            .if_break => |ib| {
                if (stack_len >= stack.len) return null;
                stack[stack_len] = ib.flat;
                stack_len += 1;
            },
        }
    }

    return if (width > remaining) null else width;
}

// Tests
const testing = std.testing;
const DocBuilder = doc.DocBuilder;

test "printer: simple text" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const d = try builder.text("hello");
    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("hello", result);
}

test "printer: concat" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const parts = try builder.arena.allocator().alloc(*const Doc, 2);
    parts[0] = try builder.text("hello");
    parts[1] = try builder.text(" world");
    const d = try builder.concat(parts);

    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("hello world", result);
}

test "printer: hard line" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const parts = try builder.arena.allocator().alloc(*const Doc, 3);
    parts[0] = try builder.text("line1");
    parts[1] = try builder.hardLine();
    parts[2] = try builder.text("line2");
    const d = try builder.concat(parts);

    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("line1\nline2", result);
}

test "printer: nested indent" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const inner_parts = try builder.arena.allocator().alloc(*const Doc, 2);
    inner_parts[0] = try builder.hardLine();
    inner_parts[1] = try builder.text("indented");
    const inner = try builder.concat(inner_parts);

    const nested = try builder.nest(2, inner);

    const parts = try builder.arena.allocator().alloc(*const Doc, 2);
    parts[0] = try builder.text("start");
    parts[1] = nested;
    const d = try builder.concat(parts);

    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("start\n  indented", result);
}

test "printer: group fits on line" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    // Create a group with soft line that should fit on one line
    const parts = try builder.arena.allocator().alloc(*const Doc, 3);
    parts[0] = try builder.text("a");
    parts[1] = try builder.line();
    parts[2] = try builder.text("b");
    const inner = try builder.concat(parts);
    const d = try builder.group(inner);

    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("a b", result);
}

test "printer: if_break in flat mode" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const ib = try builder.ifBreak(try builder.text("BROKEN"), try builder.text("flat"));
    const d = try builder.group(ib);

    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("flat", result);
}

test "printer: bracketed short list" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const items = try builder.arena.allocator().alloc(*const Doc, 3);
    items[0] = try builder.text("1");
    items[1] = try builder.text("2");
    items[2] = try builder.text("3");
    const d = try builder.bracketed("[", items, "]", false);

    const result = try print(testing.allocator, d);
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("[1, 2, 3]", result);
}
