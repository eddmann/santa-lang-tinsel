const std = @import("std");
const Allocator = std.mem.Allocator;

/// Document intermediate representation for pretty printing.
///
/// This tagged union represents a "document algebra" that can be rendered to a string
/// with intelligent line-breaking. The printer decides whether content fits
/// on one line (flat mode) or needs to be broken across lines (break mode).
pub const Doc = union(enum) {
    /// Empty document - produces no output
    nil,
    /// Literal text - always printed as-is
    text: []const u8,
    /// Soft line - becomes space in flat mode, newline+indent in break mode
    line,
    /// Hard line - always becomes newline+indent regardless of mode
    hard_line,
    /// Blank line - always becomes newline without indent (for blank line preservation)
    blank_line,
    /// Concatenation of documents
    concat: []const Doc,
    /// Grouping - content that should try to fit on one line
    group: *const Doc,
    /// Nesting - increases indentation level for nested content
    nest: struct { indent: usize, doc: *const Doc },
    /// Conditional - different output for flat vs break mode
    if_break: struct { broken: *const Doc, flat: *const Doc },
};

/// Builder for creating Doc structures with proper memory management
pub const DocBuilder = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator) DocBuilder {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *DocBuilder) void {
        self.arena.deinit();
    }

    fn alloc(self: *DocBuilder) Allocator {
        return self.arena.allocator();
    }

    /// Creates a text document from a string
    pub fn text(self: *DocBuilder, s: []const u8) !*const Doc {
        const doc = try self.alloc().create(Doc);
        const str = try self.alloc().dupe(u8, s);
        doc.* = .{ .text = str };
        return doc;
    }

    /// Creates a soft line (space in flat mode, newline in break mode)
    pub fn line(self: *DocBuilder) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .line;
        return doc;
    }

    /// Creates a hard line (always newline)
    pub fn hardLine(self: *DocBuilder) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .hard_line;
        return doc;
    }

    /// Creates a blank line (newline without indent, for blank line preservation)
    pub fn blankLine(self: *DocBuilder) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .blank_line;
        return doc;
    }

    /// Creates a nil document
    pub fn nil(self: *DocBuilder) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .nil;
        return doc;
    }

    /// Wraps a document in a group that tries to fit on one line
    pub fn group(self: *DocBuilder, inner: *const Doc) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .{ .group = inner };
        return doc;
    }

    /// Nests a document with additional indentation
    pub fn nest(self: *DocBuilder, indent: usize, inner: *const Doc) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .{ .nest = .{ .indent = indent, .doc = inner } };
        return doc;
    }

    /// Concatenates multiple documents, flattening nested concats and filtering nil
    pub fn concat(self: *DocBuilder, docs: []const *const Doc) !*const Doc {
        // Count non-nil docs and flatten nested concats
        var count: usize = 0;
        for (docs) |d| {
            switch (d.*) {
                .nil => {},
                .concat => |inner| count += inner.len,
                else => count += 1,
            }
        }

        if (count == 0) {
            return self.nil();
        }

        // Build flattened array
        const flattened = try self.alloc().alloc(Doc, count);
        var idx: usize = 0;
        for (docs) |d| {
            switch (d.*) {
                .nil => {},
                .concat => |inner| {
                    for (inner) |item| {
                        flattened[idx] = item;
                        idx += 1;
                    }
                },
                else => {
                    flattened[idx] = d.*;
                    idx += 1;
                },
            }
        }

        if (flattened.len == 1) {
            const doc = try self.alloc().create(Doc);
            doc.* = flattened[0];
            return doc;
        }

        const doc = try self.alloc().create(Doc);
        doc.* = .{ .concat = flattened };
        return doc;
    }

    /// Creates a conditional document with different output for flat vs break mode
    pub fn ifBreak(self: *DocBuilder, broken: *const Doc, flat: *const Doc) !*const Doc {
        const doc = try self.alloc().create(Doc);
        doc.* = .{ .if_break = .{ .broken = broken, .flat = flat } };
        return doc;
    }

    /// Joins documents with a separator between each
    pub fn join(self: *DocBuilder, docs: []const *const Doc, sep: *const Doc) !*const Doc {
        if (docs.len == 0) {
            return self.nil();
        }

        const result = try self.alloc().alloc(*const Doc, docs.len * 2 - 1);
        for (docs, 0..) |d, i| {
            result[i * 2] = d;
            if (i < docs.len - 1) {
                result[i * 2 + 1] = sep;
            }
        }

        return self.concat(result[0 .. docs.len * 2 - 1]);
    }

    /// Creates a soft line that becomes nothing in flat mode, newline in break mode
    pub fn softLine(self: *DocBuilder) !*const Doc {
        return self.ifBreak(try self.hardLine(), try self.nil());
    }

    /// Creates a bracketed group with smart line-breaking for collections
    /// open: opening bracket (e.g., "[")
    /// docs: elements to format
    /// close: closing bracket (e.g., "]")
    /// trailing_comma: whether to add trailing comma in break mode
    pub fn bracketed(self: *DocBuilder, open: []const u8, docs: []const *const Doc, close: []const u8, trailing_comma: bool) !*const Doc {
        if (docs.len == 0) {
            const parts = try self.alloc().alloc(*const Doc, 2);
            parts[0] = try self.text(open);
            parts[1] = try self.text(close);
            return self.concat(parts);
        }

        // Separator: ", " in flat mode, ",\n" in broken mode
        const comma_text = try self.text(",");
        const space_text = try self.text(" ");
        const sep_flat_parts = try self.alloc().alloc(*const Doc, 2);
        sep_flat_parts[0] = comma_text;
        sep_flat_parts[1] = space_text;
        const sep_flat = try self.concat(sep_flat_parts);

        const sep_broken_parts = try self.alloc().alloc(*const Doc, 2);
        sep_broken_parts[0] = comma_text;
        sep_broken_parts[1] = try self.hardLine();
        const sep_broken = try self.concat(sep_broken_parts);

        const sep = try self.ifBreak(sep_broken, sep_flat);
        const joined = try self.join(docs, sep);

        // Trailing comma only in broken mode
        const trailing = if (trailing_comma)
            try self.ifBreak(try self.text(","), try self.nil())
        else
            try self.nil();

        // Build: open + nest(2, softLine + joined + trailing) + softLine + close
        const inner_parts = try self.alloc().alloc(*const Doc, 3);
        inner_parts[0] = try self.softLine();
        inner_parts[1] = joined;
        inner_parts[2] = trailing;
        const inner = try self.concat(inner_parts);
        const nested = try self.nest(2, inner);

        const all_parts = try self.alloc().alloc(*const Doc, 4);
        all_parts[0] = try self.text(open);
        all_parts[1] = nested;
        all_parts[2] = try self.softLine();
        all_parts[3] = try self.text(close);

        return self.group(try self.concat(all_parts));
    }
};

// Tests
const testing = std.testing;

test "doc: text" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.text("hello");
    try testing.expectEqualStrings("hello", doc.text);
}

test "doc: concat" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const parts = try builder.alloc().alloc(*const Doc, 2);
    parts[0] = try builder.text("hello");
    parts[1] = try builder.text(" world");
    const doc = try builder.concat(parts);

    try testing.expectEqual(@as(usize, 2), doc.concat.len);
}

test "doc: group" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const inner = try builder.text("test");
    const doc = try builder.group(inner);

    try testing.expectEqualStrings("test", doc.group.text);
}

test "doc: nest" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const inner = try builder.text("nested");
    const doc = try builder.nest(2, inner);

    try testing.expectEqual(@as(usize, 2), doc.nest.indent);
}

test "doc: join" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const items = try builder.alloc().alloc(*const Doc, 3);
    items[0] = try builder.text("a");
    items[1] = try builder.text("b");
    items[2] = try builder.text("c");

    const sep = try builder.text(", ");
    const doc = try builder.join(items, sep);

    // Should be: a, b, c (5 elements: a + , + b + , + c)
    try testing.expectEqual(@as(usize, 5), doc.concat.len);
}

test "doc: bracketed empty" {
    var builder = DocBuilder.init(testing.allocator);
    defer builder.deinit();

    const doc = try builder.bracketed("[", &.{}, "]", false);
    try testing.expectEqual(@as(usize, 2), doc.concat.len);
}
