const std = @import("std");

pub const TokenKind = enum {
    // Special
    illegal,
    eof,

    // Literals
    identifier,
    integer,
    decimal,
    string,
    comment,
    underscore,

    // Operators
    assign, // =
    plus, // +
    minus, // -
    bang, // !
    asterisk, // *
    slash, // /
    modulo, // %

    // Comparison
    equal, // ==
    not_equal, // !=
    less_than, // <
    less_equal, // <=
    greater_than, // >
    greater_equal, // >=

    // Delimiters
    comma, // ,
    semicolon, // ;
    colon, // :
    lparen, // (
    rparen, // )
    lbrace, // {
    hash_lbrace, // #{
    rbrace, // }
    lbracket, // [
    rbracket, // ]
    backtick, // `

    // Logical/Pipe
    pipe, // |
    pipe_pipe, // ||
    amp_amp, // &&
    pipe_greater, // |>
    greater_greater, // >>

    // Range
    dot_dot, // ..
    dot_dot_equal, // ..=

    // Other
    at, // @

    // Keywords
    kw_mut,
    kw_match,
    kw_let,
    kw_if,
    kw_else,
    kw_return,
    kw_break,
    kw_nil,
    kw_true,
    kw_false,

    pub fn keyword(id: []const u8) ?TokenKind {
        const map = std.StaticStringMap(TokenKind).initComptime(.{
            .{ "mut", .kw_mut },
            .{ "match", .kw_match },
            .{ "let", .kw_let },
            .{ "if", .kw_if },
            .{ "else", .kw_else },
            .{ "return", .kw_return },
            .{ "break", .kw_break },
            .{ "nil", .kw_nil },
            .{ "true", .kw_true },
            .{ "false", .kw_false },
        });
        return map.get(id);
    }

    pub fn symbol(self: TokenKind) []const u8 {
        return switch (self) {
            .illegal => "ILLEGAL",
            .eof => "EOF",
            .identifier => "IDENTIFIER",
            .integer => "INTEGER",
            .decimal => "DECIMAL",
            .string => "STRING",
            .comment => "COMMENT",
            .underscore => "_",
            .assign => "=",
            .plus => "+",
            .minus => "-",
            .bang => "!",
            .asterisk => "*",
            .slash => "/",
            .modulo => "%",
            .equal => "==",
            .not_equal => "!=",
            .less_than => "<",
            .less_equal => "<=",
            .greater_than => ">",
            .greater_equal => ">=",
            .comma => ",",
            .semicolon => ";",
            .colon => ":",
            .lparen => "(",
            .rparen => ")",
            .lbrace => "{",
            .hash_lbrace => "#{",
            .rbrace => "}",
            .lbracket => "[",
            .rbracket => "]",
            .backtick => "`",
            .pipe => "|",
            .pipe_pipe => "||",
            .amp_amp => "&&",
            .pipe_greater => "|>",
            .greater_greater => ">>",
            .dot_dot => "..",
            .dot_dot_equal => "..=",
            .at => "@",
            .kw_mut => "mut",
            .kw_match => "match",
            .kw_let => "let",
            .kw_if => "if",
            .kw_else => "else",
            .kw_return => "return",
            .kw_break => "break",
            .kw_nil => "nil",
            .kw_true => "true",
            .kw_false => "false",
        };
    }
};

pub const Location = struct {
    start: usize,
    end: usize,

    pub fn merge(self: Location, other: Location) Location {
        return .{
            .start = @min(self.start, other.start),
            .end = @max(self.end, other.end),
        };
    }
};

pub const Token = struct {
    kind: TokenKind,
    start: usize,
    end: usize,
    line: usize,
    preceded_by_blank_line: bool,

    pub fn location(self: Token) Location {
        return .{ .start = self.start, .end = self.end };
    }

    pub fn isKeyword(self: Token) bool {
        return switch (self.kind) {
            .kw_mut, .kw_match, .kw_let, .kw_if, .kw_else, .kw_return, .kw_break, .kw_nil, .kw_true, .kw_false => true,
            else => false,
        };
    }
};
