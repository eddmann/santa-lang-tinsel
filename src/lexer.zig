const std = @import("std");
const token = @import("token.zig");
const Token = token.Token;
const TokenKind = token.TokenKind;

const EOF_CHAR: u8 = 0;
const MIN_NEWLINES_FOR_BLANK_LINE: usize = 2;

pub const Lexer = struct {
    source: []const u8,
    position: usize,
    line: usize,
    blank_lines_before: bool,
    token_buffer: ?Token,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .position = 0,
            .line = 1,
            .blank_lines_before = false,
            .token_buffer = null,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        // Return buffered token if present (for number/range lookahead)
        if (self.token_buffer) |tok| {
            self.token_buffer = null;
            return tok;
        }

        self.skipWhitespace();

        const start = self.position;
        const line = self.line;
        const blank_lines_before = self.blank_lines_before;
        self.blank_lines_before = false;

        const ch = self.consume();

        const kind: TokenKind = switch (ch) {
            '=' => if (self.peek() == '=') blk: {
                _ = self.consume();
                break :blk .equal;
            } else .assign,

            '!' => if (self.peek() == '=') blk: {
                _ = self.consume();
                break :blk .not_equal;
            } else .bang,

            '<' => if (self.peek() == '=') blk: {
                _ = self.consume();
                break :blk .less_equal;
            } else .less_than,

            '>' => switch (self.peek()) {
                '=' => blk: {
                    _ = self.consume();
                    break :blk .greater_equal;
                },
                '>' => blk: {
                    _ = self.consume();
                    break :blk .greater_greater;
                },
                else => .greater_than,
            },

            '&' => if (self.peek() == '&') blk: {
                _ = self.consume();
                break :blk .amp_amp;
            } else .illegal,

            '|' => switch (self.peek()) {
                '|' => blk: {
                    _ = self.consume();
                    break :blk .pipe_pipe;
                },
                '>' => blk: {
                    _ = self.consume();
                    break :blk .pipe_greater;
                },
                else => .pipe,
            },

            '#' => if (self.peek() == '{') blk: {
                _ = self.consume();
                break :blk .hash_lbrace;
            } else .illegal,

            '.' => if (self.peek() == '.') blk: {
                _ = self.consume();
                if (self.peek() == '=') {
                    _ = self.consume();
                    break :blk .dot_dot_equal;
                }
                break :blk .dot_dot;
            } else .illegal,

            '+' => .plus,
            '-' => .minus,
            '*' => .asterisk,
            '/' => if (self.peek() == '/') self.consumeComment() else .slash,
            '%' => .modulo,

            ';' => .semicolon,
            ',' => .comma,
            ':' => .colon,
            '(' => .lparen,
            ')' => .rparen,
            '{' => .lbrace,
            '}' => .rbrace,
            '[' => .lbracket,
            ']' => .rbracket,
            '_' => .underscore,
            '@' => .at,

            '`' => self.consumeBacktick(),
            '"' => self.consumeString(),

            '0'...'9' => return self.consumeNumber(start, line, blank_lines_before),
            'a'...'z', 'A'...'Z' => self.consumeIdentifierOrKeyword(start),

            EOF_CHAR => .eof,
            else => .illegal,
        };

        return .{
            .kind = kind,
            .start = start,
            .end = self.position,
            .line = line,
            .preceded_by_blank_line = blank_lines_before,
        };
    }

    fn consumeBacktick(self: *Lexer) TokenKind {
        while (true) {
            const ch = self.consume();
            if (ch == EOF_CHAR) return .illegal;
            if (ch == '`') break;
        }
        return .backtick;
    }

    fn consumeString(self: *Lexer) TokenKind {
        while (true) {
            const ch = self.consume();
            if (ch == EOF_CHAR) return .illegal;
            if (ch == '\\') {
                const next = self.peek();
                if (next == '\\' or next == '"' or next == 'r' or next == 'n' or next == 't' or next == 'b' or next == 'f') {
                    _ = self.consume();
                }
            } else if (ch == '"') {
                break;
            }
        }
        return .string;
    }

    fn consumeNumber(self: *Lexer, start: usize, line: usize, blank_lines_before: bool) Token {
        self.consumeWhile(isDigitOrUnderscore);

        if (self.peek() != '.') {
            return .{
                .kind = .integer,
                .start = start,
                .end = self.position,
                .line = line,
                .preceded_by_blank_line = blank_lines_before,
            };
        }

        const dot_position = self.position;
        _ = self.consume(); // consume '.'

        // Check if this is a range operator (..) or decimal
        if (self.peek() == '.') {
            _ = self.consume(); // consume second '.'
            if (self.peek() == '=') {
                _ = self.consume();
                self.token_buffer = .{
                    .kind = .dot_dot_equal,
                    .start = dot_position,
                    .end = self.position,
                    .line = line,
                    .preceded_by_blank_line = false,
                };
            } else {
                self.token_buffer = .{
                    .kind = .dot_dot,
                    .start = dot_position,
                    .end = self.position,
                    .line = line,
                    .preceded_by_blank_line = false,
                };
            }

            return .{
                .kind = .integer,
                .start = start,
                .end = dot_position,
                .line = line,
                .preceded_by_blank_line = blank_lines_before,
            };
        }

        // It's a decimal
        self.consumeWhile(isDigitOrUnderscore);

        return .{
            .kind = .decimal,
            .start = start,
            .end = self.position,
            .line = line,
            .preceded_by_blank_line = blank_lines_before,
        };
    }

    fn consumeIdentifierOrKeyword(self: *Lexer, start: usize) TokenKind {
        self.consumeWhile(isIdentifierChar);
        const identifier = self.source[start..self.position];
        return TokenKind.keyword(identifier) orelse .identifier;
    }

    fn consumeComment(self: *Lexer) TokenKind {
        self.consumeWhile(isNotNewline);
        return .comment;
    }

    fn consume(self: *Lexer) u8 {
        if (self.position >= self.source.len) return EOF_CHAR;
        const ch = self.source[self.position];
        self.position += 1;
        return ch;
    }

    fn peek(self: *Lexer) u8 {
        if (self.position >= self.source.len) return EOF_CHAR;
        return self.source[self.position];
    }

    fn consumeWhile(self: *Lexer, predicate: fn (u8) bool) void {
        while (predicate(self.peek())) {
            _ = self.consume();
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        var newline_count: usize = 0;
        while (true) {
            const ch = self.peek();
            switch (ch) {
                ' ', '\t', '\r' => {
                    _ = self.consume();
                },
                '\n' => {
                    _ = self.consume();
                    self.line += 1;
                    newline_count += 1;
                },
                else => break,
            }
        }
        self.blank_lines_before = newline_count >= MIN_NEWLINES_FOR_BLANK_LINE;
    }

    pub fn getSource(self: *const Lexer, tok: Token) []const u8 {
        return self.source[tok.start..tok.end];
    }

    /// Get the string content without quotes, unescaping escape sequences
    pub fn getStringContent(self: *const Lexer, tok: Token, allocator: std.mem.Allocator) ![]const u8 {
        // String tokens include the quotes, so skip first and last char
        const raw = self.source[tok.start + 1 .. tok.end - 1];

        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);

        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '\\' and i + 1 < raw.len) {
                const next = raw[i + 1];
                switch (next) {
                    'n' => try result.append(allocator, '\n'),
                    't' => try result.append(allocator, '\t'),
                    'r' => try result.append(allocator, '\r'),
                    'b' => try result.append(allocator, 0x08), // backspace
                    'f' => try result.append(allocator, 0x0C), // form feed
                    '\\' => try result.append(allocator, '\\'),
                    '"' => try result.append(allocator, '"'),
                    else => {
                        try result.append(allocator, raw[i]);
                        try result.append(allocator, next);
                    },
                }
                i += 2;
            } else {
                try result.append(allocator, raw[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

fn isDigitOrUnderscore(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or ch == '_';
}

fn isIdentifierChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or ch == '?';
}

fn isNotNewline(ch: u8) bool {
    return ch != '\n' and ch != EOF_CHAR;
}

// Tests
const testing = std.testing;

test "lexer: simple tokens" {
    var lexer = Lexer.init("+-*/");
    try testing.expectEqual(TokenKind.plus, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.minus, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.asterisk, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.slash, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.eof, lexer.nextToken().kind);
}

test "lexer: comparison operators" {
    var lexer = Lexer.init("== != < <= > >=");
    try testing.expectEqual(TokenKind.equal, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.not_equal, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.less_than, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.less_equal, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.greater_than, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.greater_equal, lexer.nextToken().kind);
}

test "lexer: logical operators" {
    var lexer = Lexer.init("&& || |> >>");
    try testing.expectEqual(TokenKind.amp_amp, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.pipe_pipe, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.pipe_greater, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.greater_greater, lexer.nextToken().kind);
}

test "lexer: range operators" {
    var lexer = Lexer.init(".. ..=");
    try testing.expectEqual(TokenKind.dot_dot, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.dot_dot_equal, lexer.nextToken().kind);
}

test "lexer: delimiters" {
    var lexer = Lexer.init("(){}[]#{");
    try testing.expectEqual(TokenKind.lparen, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.rparen, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.lbrace, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.rbrace, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.lbracket, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.rbracket, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.hash_lbrace, lexer.nextToken().kind);
}

test "lexer: keywords" {
    var lexer = Lexer.init("let mut if else match return break nil true false");
    try testing.expectEqual(TokenKind.kw_let, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_mut, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_if, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_else, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_match, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_return, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_break, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_nil, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_true, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.kw_false, lexer.nextToken().kind);
}

test "lexer: identifier" {
    var lexer = Lexer.init("foo bar_baz isValid?");
    const tok1 = lexer.nextToken();
    try testing.expectEqual(TokenKind.identifier, tok1.kind);
    try testing.expectEqualStrings("foo", lexer.getSource(tok1));

    const tok2 = lexer.nextToken();
    try testing.expectEqual(TokenKind.identifier, tok2.kind);
    try testing.expectEqualStrings("bar_baz", lexer.getSource(tok2));

    const tok3 = lexer.nextToken();
    try testing.expectEqual(TokenKind.identifier, tok3.kind);
    try testing.expectEqualStrings("isValid?", lexer.getSource(tok3));
}

test "lexer: integers" {
    var lexer = Lexer.init("42 1_000_000");
    const tok1 = lexer.nextToken();
    try testing.expectEqual(TokenKind.integer, tok1.kind);
    try testing.expectEqualStrings("42", lexer.getSource(tok1));

    const tok2 = lexer.nextToken();
    try testing.expectEqual(TokenKind.integer, tok2.kind);
    try testing.expectEqualStrings("1_000_000", lexer.getSource(tok2));
}

test "lexer: decimals" {
    var lexer = Lexer.init("3.14 1_000.50");
    const tok1 = lexer.nextToken();
    try testing.expectEqual(TokenKind.decimal, tok1.kind);
    try testing.expectEqualStrings("3.14", lexer.getSource(tok1));

    const tok2 = lexer.nextToken();
    try testing.expectEqual(TokenKind.decimal, tok2.kind);
    try testing.expectEqualStrings("1_000.50", lexer.getSource(tok2));
}

test "lexer: number followed by range" {
    var lexer = Lexer.init("1..10");
    const tok1 = lexer.nextToken();
    try testing.expectEqual(TokenKind.integer, tok1.kind);
    try testing.expectEqualStrings("1", lexer.getSource(tok1));

    try testing.expectEqual(TokenKind.dot_dot, lexer.nextToken().kind);

    const tok2 = lexer.nextToken();
    try testing.expectEqual(TokenKind.integer, tok2.kind);
    try testing.expectEqualStrings("10", lexer.getSource(tok2));
}

test "lexer: number followed by inclusive range" {
    var lexer = Lexer.init("1..=10");
    try testing.expectEqual(TokenKind.integer, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.dot_dot_equal, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.integer, lexer.nextToken().kind);
}

test "lexer: string" {
    var lexer = Lexer.init("\"hello world\"");
    const tok = lexer.nextToken();
    try testing.expectEqual(TokenKind.string, tok.kind);
    try testing.expectEqualStrings("\"hello world\"", lexer.getSource(tok));
}

test "lexer: string with escapes" {
    var lexer = Lexer.init("\"a\\nb\\tc\"");
    const tok = lexer.nextToken();
    try testing.expectEqual(TokenKind.string, tok.kind);

    const content = try lexer.getStringContent(tok, testing.allocator);
    defer testing.allocator.free(content);
    try testing.expectEqualStrings("a\nb\tc", content);
}

test "lexer: comment" {
    var lexer = Lexer.init("// this is a comment\n42");
    const tok1 = lexer.nextToken();
    try testing.expectEqual(TokenKind.comment, tok1.kind);
    try testing.expectEqualStrings("// this is a comment", lexer.getSource(tok1));

    try testing.expectEqual(TokenKind.integer, lexer.nextToken().kind);
}

test "lexer: blank line detection" {
    var lexer = Lexer.init("1\n\n2");
    const tok1 = lexer.nextToken();
    try testing.expectEqual(TokenKind.integer, tok1.kind);
    try testing.expect(!tok1.preceded_by_blank_line);

    const tok2 = lexer.nextToken();
    try testing.expectEqual(TokenKind.integer, tok2.kind);
    try testing.expect(tok2.preceded_by_blank_line);
}

test "lexer: no blank line for single newline" {
    var lexer = Lexer.init("1\n2");
    const tok1 = lexer.nextToken();
    try testing.expect(!tok1.preceded_by_blank_line);

    const tok2 = lexer.nextToken();
    try testing.expect(!tok2.preceded_by_blank_line);
}

test "lexer: pipe operator" {
    var lexer = Lexer.init("|x| x");
    try testing.expectEqual(TokenKind.pipe, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.identifier, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.pipe, lexer.nextToken().kind);
    try testing.expectEqual(TokenKind.identifier, lexer.nextToken().kind);
}

test "lexer: backtick" {
    var lexer = Lexer.init("`add`");
    const tok = lexer.nextToken();
    try testing.expectEqual(TokenKind.backtick, tok.kind);
    try testing.expectEqualStrings("`add`", lexer.getSource(tok));
}
