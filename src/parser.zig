const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const Location = token_mod.Location;
const ast = @import("ast.zig");
const Program = ast.Program;
const Statement = ast.Statement;
const StatementKind = ast.StatementKind;
const Expression = ast.Expression;
const ExpressionKind = ast.ExpressionKind;
const MatchCase = ast.MatchCase;
const DictEntry = ast.DictEntry;
const Section = ast.Section;
const Attribute = ast.Attribute;
const Prefix = ast.Prefix;
const Infix = ast.Infix;

pub const ParseError = error{
    UnexpectedToken,
    OutOfMemory,
    InvalidSyntax,
};

const Precedence = enum(u8) {
    lowest = 0,
    assign, // = (right-to-left, very low)
    and_or, // && ||
    equals, // == !=
    less_greater, // < <= > >=
    composition, // >> |> .. ..=
    sum, // + -
    product, // * / % `backtick`
    prefix, // ! -
    call, // ()
    index, // []
};

fn tokenPrecedence(kind: TokenKind) Precedence {
    return switch (kind) {
        .assign => .assign,
        .amp_amp, .pipe_pipe => .and_or,
        .equal, .not_equal => .equals,
        .less_than, .less_equal, .greater_than, .greater_equal => .less_greater,
        .pipe_greater, .greater_greater, .dot_dot, .dot_dot_equal => .composition,
        .plus, .minus => .sum,
        .asterisk, .slash, .modulo, .backtick => .product,
        .lparen, .pipe => .call, // .pipe for trailing lambda syntax: `map |x| x + 1`
        .lbracket => .index,
        else => .lowest,
    };
}

pub const Parser = struct {
    lexer: *Lexer,
    current_token: Token,
    peek_token: Token,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, lexer: *Lexer) Parser {
        var parser = Parser{
            .lexer = lexer,
            .current_token = undefined,
            .peek_token = undefined,
            .allocator = allocator,
        };
        // Read two tokens to initialize current and peek
        parser.nextToken();
        parser.nextToken();
        return parser;
    }

    fn nextToken(self: *Parser) void {
        self.current_token = self.peek_token;
        self.peek_token = self.lexer.nextToken();
    }

    fn currentIs(self: *Parser, kind: TokenKind) bool {
        return self.current_token.kind == kind;
    }

    fn peekIs(self: *Parser, kind: TokenKind) bool {
        return self.peek_token.kind == kind;
    }

    fn expectPeek(self: *Parser, kind: TokenKind) ParseError!void {
        if (self.peekIs(kind)) {
            self.nextToken();
        } else {
            return ParseError.UnexpectedToken;
        }
    }

    fn peekPrecedence(self: *Parser) Precedence {
        return tokenPrecedence(self.peek_token.kind);
    }

    fn currentPrecedence(self: *Parser) Precedence {
        return tokenPrecedence(self.current_token.kind);
    }

    pub fn parse(self: *Parser) ParseError!Program {
        var statements: std.ArrayList(Statement) = .empty;
        errdefer {
            for (statements.items) |*stmt| {
                stmt.deinit(self.allocator);
            }
            if (statements.capacity > 0) statements.deinit(self.allocator);
        }

        const start = self.current_token.start;

        while (!self.currentIs(.eof)) {
            const stmt = try self.parseStatement();
            try statements.append(self.allocator, stmt);
        }

        const end = if (statements.items.len > 0)
            statements.items[statements.items.len - 1].source.end
        else
            start;

        return Program{
            .statements = try statements.toOwnedSlice(self.allocator),
            .source = .{ .start = start, .end = end },
        };
    }

    fn parseStatement(self: *Parser) ParseError!Statement {
        const start_token = self.current_token;
        const preceded_by_blank = start_token.preceded_by_blank_line;

        // Check for attributes before sections
        var attributes: std.ArrayList(Attribute) = .empty;
        errdefer {
            for (attributes.items) |attr| {
                self.allocator.free(attr.name);
            }
            if (attributes.capacity > 0) attributes.deinit(self.allocator);
        }

        while (self.currentIs(.at)) {
            self.nextToken(); // consume @
            if (!self.currentIs(.identifier)) {
                return ParseError.UnexpectedToken;
            }
            const attr_name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
            try attributes.append(self.allocator, .{
                .name = attr_name,
                .source = self.current_token.location(),
            });
            self.nextToken();
        }

        const kind: StatementKind = switch (self.current_token.kind) {
            .kw_return => blk: {
                self.nextToken();
                const expr = try self.parseExpression(.lowest);
                break :blk .{ .@"return" = expr };
            },
            .kw_break => blk: {
                self.nextToken();
                const expr = try self.parseExpression(.lowest);
                break :blk .{ .@"break" = expr };
            },
            .comment => blk: {
                const comment_text = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{ .comment = comment_text };
            },
            .identifier => blk: {
                // Check if this is a section (identifier followed by colon)
                if (self.peekIs(.colon)) {
                    const section = try self.parseSection(try attributes.toOwnedSlice(self.allocator));
                    break :blk .{ .section = section };
                } else {
                    // Free unused attributes
                    for (attributes.items) |attr| {
                        self.allocator.free(attr.name);
                    }
                    if (attributes.capacity > 0) attributes.deinit(self.allocator);
                    const expr = try self.parseExpression(.lowest);
                    break :blk .{ .expression = expr };
                }
            },
            else => blk: {
                // Free unused attributes
                for (attributes.items) |attr| {
                    self.allocator.free(attr.name);
                }
                if (attributes.capacity > 0) attributes.deinit(self.allocator);
                const expr = try self.parseExpression(.lowest);
                break :blk .{ .expression = expr };
            },
        };

        // Skip optional semicolon
        if (self.currentIs(.semicolon)) {
            self.nextToken();
        }

        // Check for trailing comment on same line
        var trailing_comment: ?[]const u8 = null;
        if (self.currentIs(.comment) and self.current_token.line == start_token.line) {
            trailing_comment = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
            self.nextToken();
        }

        const end = self.current_token.start;

        return Statement{
            .kind = kind,
            .source = .{ .start = start_token.start, .end = end },
            .preceded_by_blank_line = preceded_by_blank,
            .trailing_comment = trailing_comment,
        };
    }

    fn parseSection(self: *Parser, attributes: []Attribute) ParseError!Section {
        const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
        errdefer self.allocator.free(name);

        self.nextToken(); // move past identifier
        // current is now colon
        if (!self.currentIs(.colon)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken(); // move past colon to body

        // Parse body - either braced block or single expression
        const body = try self.allocator.create(Program);
        errdefer self.allocator.destroy(body);

        if (self.currentIs(.lbrace)) {
            self.nextToken(); // consume {
            var stmts: std.ArrayList(Statement) = .empty;
            errdefer {
                for (stmts.items) |*s| s.deinit(self.allocator);
                if (stmts.capacity > 0) stmts.deinit(self.allocator);
            }

            while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
                const stmt = try self.parseStatement();
                try stmts.append(self.allocator, stmt);
            }

            if (!self.currentIs(.rbrace)) {
                return ParseError.UnexpectedToken;
            }
            self.nextToken(); // consume }

            body.* = .{
                .statements = try stmts.toOwnedSlice(self.allocator),
                .source = .{ .start = 0, .end = 0 },
            };
        } else {
            // Single expression - capture the start line for trailing comment detection
            const expr_start_line = self.current_token.line;
            const expr = try self.parseExpression(.lowest);

            // Check for trailing comment on same line as expression start
            var trailing_comment: ?[]const u8 = null;
            if (self.currentIs(.comment) and self.current_token.line == expr_start_line) {
                trailing_comment = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
            }

            const stmt = try self.allocator.alloc(Statement, 1);
            stmt[0] = .{
                .kind = .{ .expression = expr },
                .source = expr.source,
                .preceded_by_blank_line = false,
                .trailing_comment = trailing_comment,
            };
            body.* = .{
                .statements = stmt,
                .source = expr.source,
            };
        }

        return Section{
            .name = name,
            .body = body,
            .attributes = attributes,
        };
    }

    fn parseExpression(self: *Parser, precedence: Precedence) ParseError!*Expression {
        // Parse prefix
        var left = try self.parsePrefixExpression();

        // Parse infix - note: after prefix parsing, current_token is the potential operator
        while (!self.currentIs(.eof) and @intFromEnum(precedence) < @intFromEnum(self.currentPrecedence())) {
            const current_kind = self.current_token.kind;

            // Handle pipe chains and composition specially to collect all functions
            if (current_kind == .pipe_greater) {
                left = try self.parsePipeChain(left);
                continue;
            }
            if (current_kind == .greater_greater) {
                left = try self.parseComposition(left);
                continue;
            }

            switch (current_kind) {
                .plus, .minus, .asterisk, .slash, .modulo, .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal, .amp_amp, .pipe_pipe, .backtick, .dot_dot, .dot_dot_equal, .assign => {
                    left = try self.parseInfixExpression(left);
                },
                .lparen => {
                    self.nextToken(); // advance past (
                    left = try self.parseCallExpression(left);
                },
                .lbracket => {
                    left = try self.parseIndexExpression(left);
                },
                .pipe => {
                    // Trailing lambda syntax: `map |x| x + 1` is equivalent to `map(|x| x + 1)`
                    left = try self.parseTrailingLambdaCall(left);
                },
                else => break,
            }
        }

        return left;
    }

    fn parsePrefixExpression(self: *Parser) ParseError!*Expression {
        const expr = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(expr);

        const start = self.current_token.start;

        expr.* = switch (self.current_token.kind) {
            .integer => blk: {
                const value = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .integer = value },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .decimal => blk: {
                const value = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .decimal = value },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .string => blk: {
                const value = try self.lexer.getStringContent(self.current_token, self.allocator);
                self.nextToken();
                break :blk .{
                    .kind = .{ .string = value },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .kw_true => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .{ .boolean = true },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .kw_false => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .{ .boolean = false },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .kw_nil => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .nil,
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .underscore => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .placeholder,
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .identifier => blk: {
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .bang => blk: {
                self.nextToken();
                const right = try self.parseExpression(.prefix);
                break :blk .{
                    .kind = .{ .prefix = .{ .operator = .bang, .right = right } },
                    .source = .{ .start = start, .end = right.source.end },
                };
            },
            .minus => blk: {
                self.nextToken();
                const right = try self.parseExpression(.prefix);
                break :blk .{
                    .kind = .{ .prefix = .{ .operator = .minus, .right = right } },
                    .source = .{ .start = start, .end = right.source.end },
                };
            },
            .lparen => blk: {
                self.nextToken();
                const inner = try self.parseExpression(.lowest);
                if (!self.currentIs(.rparen)) {
                    return ParseError.UnexpectedToken;
                }
                self.nextToken();
                // Return the inner expression, adjusting source location
                expr.* = inner.*;
                // Don't destroy inner since we're reusing its contents
                self.allocator.destroy(inner);
                break :blk expr.*;
            },
            .lbracket => try self.parseListOrPattern(),
            .lbrace => try self.parseSet(),
            .hash_lbrace => try self.parseDictionary(),
            .pipe, .pipe_pipe => try self.parseLambda(),
            .kw_if => try self.parseIfExpression(),
            .kw_match => try self.parseMatchExpression(),
            .kw_let => try self.parseLetExpression(),
            .dot_dot => blk: {
                // Rest identifier like ..rest
                self.nextToken();
                if (!self.currentIs(.identifier)) {
                    return ParseError.UnexpectedToken;
                }
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .rest_identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            // Operator references - operators used as first-class values, e.g., sort(<)
            .less_than,
            .less_equal,
            .greater_than,
            .greater_equal,
            .plus,
            .asterisk,
            .slash,
            .modulo,
            .equal,
            .not_equal,
            .amp_amp,
            => blk: {
                const op_symbol = switch (self.current_token.kind) {
                    .less_than => "<",
                    .less_equal => "<=",
                    .greater_than => ">",
                    .greater_equal => ">=",
                    .plus => "+",
                    .asterisk => "*",
                    .slash => "/",
                    .modulo => "%",
                    .equal => "==",
                    .not_equal => "!=",
                    .amp_amp => "&&",
                    else => unreachable,
                };
                const symbol = try self.allocator.dupe(u8, op_symbol);
                self.nextToken();
                break :blk .{
                    .kind = .{ .operator_ref = symbol },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            else => return ParseError.UnexpectedToken,
        };

        return expr;
    }

    fn parseInfixExpression(self: *Parser, left: *Expression) ParseError!*Expression {
        const expr = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(expr);

        const op_token = self.current_token;
        const prec = self.currentPrecedence();

        // Handle assignment specially - it's not an infix operator, it creates an assign expression
        if (op_token.kind == .assign) {
            self.nextToken();
            const value = try self.parseExpression(.lowest); // right-to-left, use lowest precedence
            expr.* = .{
                .kind = .{ .assign = .{ .name = left, .value = value } },
                .source = .{ .start = left.source.start, .end = value.source.end },
            };
            return expr;
        }

        // Handle range operators specially
        if (op_token.kind == .dot_dot) {
            self.nextToken();
            // Check if this is an unbounded range
            if (self.currentIs(.eof) or self.currentIs(.rparen) or self.currentIs(.rbracket) or
                self.currentIs(.rbrace) or self.currentIs(.comma) or self.currentIs(.semicolon) or
                self.currentIs(.pipe) or self.currentIs(.pipe_greater))
            {
                expr.* = .{
                    .kind = .{ .unbounded_range = .{ .from = left } },
                    .source = .{ .start = left.source.start, .end = op_token.end },
                };
                return expr;
            }
            const right = try self.parseExpression(prec);
            expr.* = .{
                .kind = .{ .exclusive_range = .{ .from = left, .until = right } },
                .source = .{ .start = left.source.start, .end = right.source.end },
            };
            return expr;
        }

        if (op_token.kind == .dot_dot_equal) {
            self.nextToken();
            const right = try self.parseExpression(prec);
            expr.* = .{
                .kind = .{ .inclusive_range = .{ .from = left, .to = right } },
                .source = .{ .start = left.source.start, .end = right.source.end },
            };
            return expr;
        }

        // Handle backtick operator
        if (op_token.kind == .backtick) {
            // Get the identifier inside backticks
            const backtick_source = self.lexer.getSource(op_token);
            // Strip the backticks to get the function name
            const func_name = backtick_source[1 .. backtick_source.len - 1];

            const func_ident = try self.allocator.create(Expression);
            func_ident.* = .{
                .kind = .{ .identifier = try self.allocator.dupe(u8, func_name) },
                .source = op_token.location(),
            };

            self.nextToken();
            const right = try self.parseExpression(prec);

            expr.* = .{
                .kind = .{ .infix = .{
                    .operator = .{ .call = func_ident },
                    .left = left,
                    .right = right,
                } },
                .source = .{ .start = left.source.start, .end = right.source.end },
            };
            return expr;
        }

        const op: Infix = switch (op_token.kind) {
            .plus => .plus,
            .minus => .minus,
            .asterisk => .asterisk,
            .slash => .slash,
            .modulo => .modulo,
            .equal => .equal,
            .not_equal => .not_equal,
            .less_than => .less_than,
            .less_equal => .less_equal,
            .greater_than => .greater_than,
            .greater_equal => .greater_equal,
            .amp_amp => .@"and",
            .pipe_pipe => .@"or",
            else => return ParseError.UnexpectedToken,
        };

        self.nextToken();
        const right = try self.parseExpression(prec);

        expr.* = .{
            .kind = .{ .infix = .{ .operator = op, .left = left, .right = right } },
            .source = .{ .start = left.source.start, .end = right.source.end },
        };

        return expr;
    }

    fn parsePipeChain(self: *Parser, initial: *Expression) ParseError!*Expression {
        var functions: std.ArrayList(*Expression) = .empty;
        errdefer {
            for (functions.items) |f| {
                f.deinit(self.allocator);
                self.allocator.destroy(f);
            }
            if (functions.capacity > 0) functions.deinit(self.allocator);
        }

        // current is |> when we enter
        while (self.currentIs(.pipe_greater)) {
            self.nextToken(); // move past |> to function
            const func = try self.parseExpression(.composition);
            try functions.append(self.allocator, func);
        }

        const expr = try self.allocator.create(Expression);
        expr.* = .{
            .kind = .{ .function_thread = .{
                .initial = initial,
                .functions = try functions.toOwnedSlice(self.allocator),
            } },
            .source = .{ .start = initial.source.start, .end = self.current_token.start },
        };

        return expr;
    }

    fn parseComposition(self: *Parser, first: *Expression) ParseError!*Expression {
        var functions: std.ArrayList(*Expression) = .empty;
        errdefer {
            for (functions.items) |f| {
                f.deinit(self.allocator);
                self.allocator.destroy(f);
            }
            if (functions.capacity > 0) functions.deinit(self.allocator);
        }

        try functions.append(self.allocator, first);

        // current is >> when we enter
        while (self.currentIs(.greater_greater)) {
            self.nextToken(); // move past >> to function
            const func = try self.parseExpression(.composition);
            try functions.append(self.allocator, func);
        }

        const expr = try self.allocator.create(Expression);
        expr.* = .{
            .kind = .{ .function_composition = try functions.toOwnedSlice(self.allocator) },
            .source = .{ .start = first.source.start, .end = self.current_token.start },
        };

        return expr;
    }

    fn parseCallExpression(self: *Parser, function: *Expression) ParseError!*Expression {
        const args = try self.parseExpressionList(.rparen);

        const expr = try self.allocator.create(Expression);
        expr.* = .{
            .kind = .{ .call = .{ .function = function, .arguments = args } },
            .source = .{ .start = function.source.start, .end = self.current_token.start },
        };

        return expr;
    }

    /// Parse trailing lambda call syntax: `map |x| x + 1` -> `map(|x| x + 1)`
    fn parseTrailingLambdaCall(self: *Parser, function: *Expression) ParseError!*Expression {
        // Current token is | (start of lambda)
        const lambda_val = try self.parseLambda();

        // Allocate the lambda on the heap
        const lambda = try self.allocator.create(Expression);
        lambda.* = lambda_val;

        // Create single-element args array with the lambda
        const args = try self.allocator.alloc(*Expression, 1);
        args[0] = lambda;

        const expr = try self.allocator.create(Expression);
        expr.* = .{
            .kind = .{ .call = .{ .function = function, .arguments = args } },
            .source = .{ .start = function.source.start, .end = lambda.source.end },
        };

        return expr;
    }

    fn parseIndexExpression(self: *Parser, left: *Expression) ParseError!*Expression {
        self.nextToken(); // move past [
        const index_expr = try self.parseExpression(.lowest);

        if (!self.currentIs(.rbracket)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken();

        const expr = try self.allocator.create(Expression);
        expr.* = .{
            .kind = .{ .index = .{ .left = left, .index_expr = index_expr } },
            .source = .{ .start = left.source.start, .end = self.current_token.start },
        };

        return expr;
    }

    fn parseListOrPattern(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;
        self.nextToken(); // consume [

        if (self.currentIs(.rbracket)) {
            self.nextToken();
            return .{
                .kind = .{ .list = &.{} },
                .source = .{ .start = start, .end = self.current_token.start },
            };
        }

        // Check first element to determine if this is a pattern or regular list
        const elements = try self.parseExpressionList(.rbracket);

        // For simplicity, we'll determine pattern vs list based on context in the formatter
        // Here we just parse as a list - the AST consumer can interpret based on context
        return .{
            .kind = .{ .list = elements },
            .source = .{ .start = start, .end = self.current_token.start },
        };
    }

    fn parseSet(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;
        self.nextToken(); // consume {

        if (self.currentIs(.rbrace)) {
            self.nextToken();
            return .{
                .kind = .{ .set = &.{} },
                .source = .{ .start = start, .end = self.current_token.start },
            };
        }

        const elements = try self.parseExpressionList(.rbrace);

        return .{
            .kind = .{ .set = elements },
            .source = .{ .start = start, .end = self.current_token.start },
        };
    }

    fn parseDictionary(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;
        self.nextToken(); // consume #{

        if (self.currentIs(.rbrace)) {
            self.nextToken();
            return .{
                .kind = .{ .dictionary = &.{} },
                .source = .{ .start = start, .end = self.current_token.start },
            };
        }

        var entries: std.ArrayList(DictEntry) = .empty;
        errdefer {
            for (entries.items) |*e| e.deinit(self.allocator);
            if (entries.capacity > 0) entries.deinit(self.allocator);
        }

        while (true) {
            // Check for rest pattern ..rest
            if (self.currentIs(.dot_dot)) {
                self.nextToken();
                if (!self.currentIs(.identifier)) {
                    return ParseError.UnexpectedToken;
                }
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                const rest_expr = try self.allocator.create(Expression);
                rest_expr.* = .{
                    .kind = .{ .rest_identifier = name },
                    .source = self.current_token.location(),
                };
                // Store as entry with same key and value
                try entries.append(self.allocator, .{ .key = rest_expr, .value = rest_expr });
                self.nextToken();
            } else {
                const key = try self.parseExpression(.lowest);

                // Check for shorthand syntax: #{foo} means #{"foo": foo}
                if (self.currentIs(.comma) or self.currentIs(.rbrace)) {
                    // Shorthand - create string key from identifier
                    if (key.kind == .identifier) {
                        const str_key = try self.allocator.create(Expression);
                        str_key.* = .{
                            .kind = .{ .string = try self.allocator.dupe(u8, key.kind.identifier) },
                            .source = key.source,
                        };
                        try entries.append(self.allocator, .{ .key = str_key, .value = key });
                    } else {
                        // Not shorthand - error
                        return ParseError.InvalidSyntax;
                    }
                } else if (self.currentIs(.colon)) {
                    self.nextToken(); // consume :
                    const value = try self.parseExpression(.lowest);
                    try entries.append(self.allocator, .{ .key = key, .value = value });
                } else {
                    return ParseError.UnexpectedToken;
                }
            }

            if (self.currentIs(.rbrace)) {
                self.nextToken();
                break;
            }

            if (!self.currentIs(.comma)) {
                return ParseError.UnexpectedToken;
            }
            self.nextToken(); // consume comma

            // Allow trailing comma
            if (self.currentIs(.rbrace)) {
                self.nextToken();
                break;
            }
        }

        return .{
            .kind = .{ .dictionary = try entries.toOwnedSlice(self.allocator) },
            .source = .{ .start = start, .end = self.current_token.start },
        };
    }

    fn parseLambda(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;

        // Parse parameters
        var params: std.ArrayList(*Expression) = .empty;
        errdefer {
            for (params.items) |p| {
                p.deinit(self.allocator);
                self.allocator.destroy(p);
            }
            if (params.capacity > 0) params.deinit(self.allocator);
        }

        // Handle || for no params
        if (self.currentIs(.pipe_pipe)) {
            self.nextToken();
        } else {
            self.nextToken(); // consume first |

            while (!self.currentIs(.pipe) and !self.currentIs(.eof)) {
                const param = try self.parseLambdaParameter();
                try params.append(self.allocator, param);

                if (self.currentIs(.comma)) {
                    self.nextToken();
                } else {
                    break;
                }
            }

            if (!self.currentIs(.pipe)) {
                return ParseError.UnexpectedToken;
            }
            self.nextToken(); // consume closing |
        }

        // Parse body
        const body = try self.allocator.create(Statement);
        errdefer self.allocator.destroy(body);

        if (self.currentIs(.lbrace)) {
            // Block body
            self.nextToken(); // consume {
            var stmts: std.ArrayList(Statement) = .empty;
            errdefer {
                for (stmts.items) |*s| s.deinit(self.allocator);
                if (stmts.capacity > 0) stmts.deinit(self.allocator);
            }

            while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
                const stmt = try self.parseStatement();
                try stmts.append(self.allocator, stmt);
            }

            if (!self.currentIs(.rbrace)) {
                return ParseError.UnexpectedToken;
            }
            self.nextToken(); // consume }

            body.* = .{
                .kind = .{ .block = try stmts.toOwnedSlice(self.allocator) },
                .source = .{ .start = start, .end = self.current_token.start },
                .preceded_by_blank_line = false,
                .trailing_comment = null,
            };
        } else {
            // Expression body
            const expr = try self.parseExpression(.lowest);
            body.* = .{
                .kind = .{ .expression = expr },
                .source = expr.source,
                .preceded_by_blank_line = false,
                .trailing_comment = null,
            };
        }

        return .{
            .kind = .{ .function = .{
                .parameters = try params.toOwnedSlice(self.allocator),
                .body = body,
            } },
            .source = .{ .start = start, .end = body.source.end },
        };
    }

    fn parseLambdaParameter(self: *Parser) ParseError!*Expression {
        const param = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(param);

        const start = self.current_token.start;

        param.* = switch (self.current_token.kind) {
            .identifier => blk: {
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .underscore => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .placeholder,
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .dot_dot => blk: {
                self.nextToken();
                if (!self.currentIs(.identifier)) {
                    return ParseError.UnexpectedToken;
                }
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .rest_identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .lbracket => blk: {
                self.nextToken(); // consume [
                const elements = try self.parseExpressionList(.rbracket);
                break :blk .{
                    .kind = .{ .identifier_list_pattern = elements },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .hash_lbrace => blk: {
                // Parse dictionary pattern #{a, b} or #{"key": a}
                self.nextToken(); // consume #{
                var pattern_elems: std.ArrayList(*Expression) = .empty;
                errdefer {
                    for (pattern_elems.items) |e| {
                        e.deinit(self.allocator);
                        self.allocator.destroy(e);
                    }
                    if (pattern_elems.capacity > 0) pattern_elems.deinit(self.allocator);
                }

                while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
                    if (self.currentIs(.dot_dot)) {
                        // Rest pattern
                        self.nextToken();
                        if (!self.currentIs(.identifier)) {
                            return ParseError.UnexpectedToken;
                        }
                        const rest = try self.allocator.create(Expression);
                        rest.* = .{
                            .kind = .{ .rest_identifier = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token)) },
                            .source = self.current_token.location(),
                        };
                        try pattern_elems.append(self.allocator, rest);
                        self.nextToken();
                    } else {
                        const elem = try self.parseDictPatternElement();
                        try pattern_elems.append(self.allocator, elem);
                    }

                    if (self.currentIs(.comma)) {
                        self.nextToken();
                    } else {
                        break;
                    }
                }

                if (!self.currentIs(.rbrace)) {
                    return ParseError.UnexpectedToken;
                }
                self.nextToken();

                break :blk .{
                    .kind = .{ .identifier_dict_pattern = try pattern_elems.toOwnedSlice(self.allocator) },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            else => return ParseError.UnexpectedToken,
        };

        return param;
    }

    fn parseDictPatternElement(self: *Parser) ParseError!*Expression {
        const elem = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(elem);

        const start = self.current_token.start;

        if (self.currentIs(.identifier)) {
            // Could be shorthand #{a} or explicit #{"key": a}
            const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
            self.nextToken();

            if (self.currentIs(.colon)) {
                // Explicit key: value
                self.nextToken();
                const value = try self.parseLambdaParameter();
                const key_expr = try self.allocator.create(Expression);
                key_expr.* = .{
                    .kind = .{ .identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
                elem.* = .{
                    .kind = .{ .dict_entry_pattern = .{ .key = key_expr, .value = value } },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            } else {
                // Shorthand - identifier only
                elem.* = .{
                    .kind = .{ .identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            }
        } else if (self.currentIs(.string)) {
            // String key
            const key_str = try self.lexer.getStringContent(self.current_token, self.allocator);
            self.nextToken();

            if (!self.currentIs(.colon)) {
                return ParseError.UnexpectedToken;
            }
            self.nextToken();

            const value = try self.parseLambdaParameter();
            const key_expr = try self.allocator.create(Expression);
            key_expr.* = .{
                .kind = .{ .string = key_str },
                .source = .{ .start = start, .end = self.current_token.start },
            };
            elem.* = .{
                .kind = .{ .dict_entry_pattern = .{ .key = key_expr, .value = value } },
                .source = .{ .start = start, .end = self.current_token.start },
            };
        } else {
            return ParseError.UnexpectedToken;
        }

        return elem;
    }

    fn parseIfExpression(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;
        self.nextToken(); // consume 'if'

        // Parse condition (optionally parenthesized)
        const condition = try self.parseExpression(.lowest);

        // Parse consequence
        if (!self.currentIs(.lbrace)) {
            return ParseError.UnexpectedToken;
        }
        const consequence = try self.parseBlockStatement();

        // Parse optional else
        var alternative: ?*Statement = null;
        if (self.currentIs(.kw_else)) {
            self.nextToken();
            alternative = try self.parseBlockStatement();
        }

        return .{
            .kind = .{ .@"if" = .{
                .condition = condition,
                .consequence = consequence,
                .alternative = alternative,
            } },
            .source = .{ .start = start, .end = self.current_token.start },
        };
    }

    fn parseMatchExpression(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;
        self.nextToken(); // consume 'match'

        const subject = try self.parseExpression(.lowest);

        if (!self.currentIs(.lbrace)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken(); // consume {

        var cases: std.ArrayList(MatchCase) = .empty;
        errdefer {
            for (cases.items) |*c| c.deinit(self.allocator);
            if (cases.capacity > 0) cases.deinit(self.allocator);
        }

        while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
            const case = try self.parseMatchCase();
            try cases.append(self.allocator, case);
        }

        if (!self.currentIs(.rbrace)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken();

        return .{
            .kind = .{ .match = .{
                .subject = subject,
                .cases = try cases.toOwnedSlice(self.allocator),
            } },
            .source = .{ .start = start, .end = self.current_token.start },
        };
    }

    fn parseMatchCase(self: *Parser) ParseError!MatchCase {
        const pattern = try self.parseMatchPattern();

        // Check for guard
        var guard: ?*Expression = null;
        if (self.currentIs(.kw_if)) {
            self.nextToken();
            guard = try self.parseExpression(.lowest);
        }

        // Parse consequence
        if (!self.currentIs(.lbrace)) {
            return ParseError.UnexpectedToken;
        }
        const consequence = try self.parseBlockStatement();

        // Check for trailing comment on same line as closing brace
        var trailing_comment: ?[]const u8 = null;
        if (self.currentIs(.comment)) {
            trailing_comment = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
            self.nextToken();
        }

        return .{
            .pattern = pattern,
            .guard = guard,
            .consequence = consequence,
            .trailing_comment = trailing_comment,
        };
    }

    fn parseMatchPattern(self: *Parser) ParseError!*Expression {
        const pattern = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(pattern);

        const start = self.current_token.start;

        pattern.* = switch (self.current_token.kind) {
            .integer => blk: {
                const value = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .integer = value },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .decimal => blk: {
                const value = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .decimal = value },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .string => blk: {
                const value = try self.lexer.getStringContent(self.current_token, self.allocator);
                self.nextToken();
                break :blk .{
                    .kind = .{ .string = value },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .kw_true => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .{ .boolean = true },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .kw_false => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .{ .boolean = false },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .kw_nil => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .nil,
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .underscore => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .placeholder,
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .identifier => blk: {
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .lbracket => blk: {
                self.nextToken();
                var elements: std.ArrayList(*Expression) = .empty;
                errdefer {
                    for (elements.items) |e| {
                        e.deinit(self.allocator);
                        self.allocator.destroy(e);
                    }
                    if (elements.capacity > 0) elements.deinit(self.allocator);
                }

                while (!self.currentIs(.rbracket) and !self.currentIs(.eof)) {
                    if (self.currentIs(.dot_dot)) {
                        // Rest pattern
                        self.nextToken();
                        if (self.currentIs(.identifier)) {
                            const rest = try self.allocator.create(Expression);
                            rest.* = .{
                                .kind = .{ .rest_identifier = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token)) },
                                .source = self.current_token.location(),
                            };
                            try elements.append(self.allocator, rest);
                            self.nextToken();
                        } else {
                            // Spread expression
                            const inner = try self.parseMatchPattern();
                            const spread = try self.allocator.create(Expression);
                            spread.* = .{
                                .kind = .{ .spread = inner },
                                .source = inner.source,
                            };
                            try elements.append(self.allocator, spread);
                        }
                    } else {
                        const elem = try self.parseMatchPattern();
                        try elements.append(self.allocator, elem);
                    }

                    if (self.currentIs(.comma)) {
                        self.nextToken();
                    } else {
                        break;
                    }
                }

                if (!self.currentIs(.rbracket)) {
                    return ParseError.UnexpectedToken;
                }
                self.nextToken();

                break :blk .{
                    .kind = .{ .list_match_pattern = try elements.toOwnedSlice(self.allocator) },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .hash_lbrace => blk: {
                self.nextToken();
                var elements: std.ArrayList(*Expression) = .empty;
                errdefer {
                    for (elements.items) |e| {
                        e.deinit(self.allocator);
                        self.allocator.destroy(e);
                    }
                    if (elements.capacity > 0) elements.deinit(self.allocator);
                }

                while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
                    if (self.currentIs(.dot_dot)) {
                        self.nextToken();
                        if (self.currentIs(.identifier)) {
                            const rest = try self.allocator.create(Expression);
                            rest.* = .{
                                .kind = .{ .rest_identifier = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token)) },
                                .source = self.current_token.location(),
                            };
                            try elements.append(self.allocator, rest);
                            self.nextToken();
                        }
                    } else {
                        const elem = try self.parseDictPatternElement();
                        try elements.append(self.allocator, elem);
                    }

                    if (self.currentIs(.comma)) {
                        self.nextToken();
                    } else {
                        break;
                    }
                }

                if (!self.currentIs(.rbrace)) {
                    return ParseError.UnexpectedToken;
                }
                self.nextToken();

                break :blk .{
                    .kind = .{ .dict_match_pattern = try elements.toOwnedSlice(self.allocator) },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            else => return ParseError.UnexpectedToken,
        };

        return pattern;
    }

    fn parseLetExpression(self: *Parser) ParseError!Expression {
        const start = self.current_token.start;
        self.nextToken(); // consume 'let'

        const is_mutable = self.currentIs(.kw_mut);
        if (is_mutable) {
            self.nextToken();
        }

        // Parse name/pattern
        const name = try self.parseLetPattern();

        if (!self.currentIs(.assign)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken();

        const value = try self.parseExpression(.lowest);

        if (is_mutable) {
            return .{
                .kind = .{ .mutable_let = .{ .name = name, .value = value } },
                .source = .{ .start = start, .end = value.source.end },
            };
        } else {
            return .{
                .kind = .{ .let = .{ .name = name, .value = value } },
                .source = .{ .start = start, .end = value.source.end },
            };
        }
    }

    fn parseLetPattern(self: *Parser) ParseError!*Expression {
        const pattern = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(pattern);

        const start = self.current_token.start;

        pattern.* = switch (self.current_token.kind) {
            .identifier => blk: {
                const name = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token));
                self.nextToken();
                break :blk .{
                    .kind = .{ .identifier = name },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .underscore => blk: {
                self.nextToken();
                break :blk .{
                    .kind = .placeholder,
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .lbracket => blk: {
                self.nextToken();
                var elements: std.ArrayList(*Expression) = .empty;
                errdefer {
                    for (elements.items) |e| {
                        e.deinit(self.allocator);
                        self.allocator.destroy(e);
                    }
                    if (elements.capacity > 0) elements.deinit(self.allocator);
                }

                while (!self.currentIs(.rbracket) and !self.currentIs(.eof)) {
                    if (self.currentIs(.dot_dot)) {
                        self.nextToken();
                        if (self.currentIs(.identifier)) {
                            const rest = try self.allocator.create(Expression);
                            rest.* = .{
                                .kind = .{ .rest_identifier = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token)) },
                                .source = self.current_token.location(),
                            };
                            try elements.append(self.allocator, rest);
                            self.nextToken();
                        }
                    } else {
                        const elem = try self.parseLetPattern();
                        try elements.append(self.allocator, elem);
                    }

                    if (self.currentIs(.comma)) {
                        self.nextToken();
                    } else {
                        break;
                    }
                }

                if (!self.currentIs(.rbracket)) {
                    return ParseError.UnexpectedToken;
                }
                self.nextToken();

                break :blk .{
                    .kind = .{ .identifier_list_pattern = try elements.toOwnedSlice(self.allocator) },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            .hash_lbrace => blk: {
                self.nextToken();
                var elements: std.ArrayList(*Expression) = .empty;
                errdefer {
                    for (elements.items) |e| {
                        e.deinit(self.allocator);
                        self.allocator.destroy(e);
                    }
                    if (elements.capacity > 0) elements.deinit(self.allocator);
                }

                while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
                    if (self.currentIs(.dot_dot)) {
                        self.nextToken();
                        if (self.currentIs(.identifier)) {
                            const rest = try self.allocator.create(Expression);
                            rest.* = .{
                                .kind = .{ .rest_identifier = try self.allocator.dupe(u8, self.lexer.getSource(self.current_token)) },
                                .source = self.current_token.location(),
                            };
                            try elements.append(self.allocator, rest);
                            self.nextToken();
                        }
                    } else {
                        const elem = try self.parseDictPatternElement();
                        try elements.append(self.allocator, elem);
                    }

                    if (self.currentIs(.comma)) {
                        self.nextToken();
                    } else {
                        break;
                    }
                }

                if (!self.currentIs(.rbrace)) {
                    return ParseError.UnexpectedToken;
                }
                self.nextToken();

                break :blk .{
                    .kind = .{ .identifier_dict_pattern = try elements.toOwnedSlice(self.allocator) },
                    .source = .{ .start = start, .end = self.current_token.start },
                };
            },
            else => return ParseError.UnexpectedToken,
        };

        return pattern;
    }

    fn parseBlockStatement(self: *Parser) ParseError!*Statement {
        const stmt = try self.allocator.create(Statement);
        errdefer self.allocator.destroy(stmt);

        const start = self.current_token.start;
        self.nextToken(); // consume {

        var stmts: std.ArrayList(Statement) = .empty;
        errdefer {
            for (stmts.items) |*s| s.deinit(self.allocator);
            if (stmts.capacity > 0) stmts.deinit(self.allocator);
        }

        while (!self.currentIs(.rbrace) and !self.currentIs(.eof)) {
            const inner = try self.parseStatement();
            try stmts.append(self.allocator, inner);
        }

        if (!self.currentIs(.rbrace)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken();

        stmt.* = .{
            .kind = .{ .block = try stmts.toOwnedSlice(self.allocator) },
            .source = .{ .start = start, .end = self.current_token.start },
            .preceded_by_blank_line = false,
            .trailing_comment = null,
        };

        return stmt;
    }

    fn parseExpressionList(self: *Parser, end_token: TokenKind) ParseError![]*Expression {
        var exprs: std.ArrayList(*Expression) = .empty;
        errdefer {
            for (exprs.items) |e| {
                e.deinit(self.allocator);
                self.allocator.destroy(e);
            }
            if (exprs.capacity > 0) exprs.deinit(self.allocator);
        }

        while (!self.currentIs(end_token) and !self.currentIs(.eof)) {
            // Check for spread/rest
            if (self.currentIs(.dot_dot)) {
                self.nextToken();
                const inner = try self.parseExpression(.lowest);
                const spread = try self.allocator.create(Expression);
                spread.* = .{
                    .kind = .{ .spread = inner },
                    .source = inner.source,
                };
                try exprs.append(self.allocator, spread);
            } else {
                const expr = try self.parseExpression(.lowest);
                try exprs.append(self.allocator, expr);
            }

            if (self.currentIs(.comma)) {
                self.nextToken();
            } else {
                break;
            }
        }

        if (!self.currentIs(end_token)) {
            return ParseError.UnexpectedToken;
        }
        self.nextToken();

        return exprs.toOwnedSlice(self.allocator);
    }
};

// Tests
const testing = std.testing;

test "parser: integer literal" {
    var lexer = Lexer.init("42");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), program.statements.len);
    const expr = program.statements[0].kind.expression;
    try testing.expectEqualStrings("42", expr.kind.integer);
}

test "parser: string literal" {
    var lexer = Lexer.init("\"hello\"");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), program.statements.len);
    const expr = program.statements[0].kind.expression;
    try testing.expectEqualStrings("hello", expr.kind.string);
}

test "parser: infix expression" {
    var lexer = Lexer.init("1 + 2");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), program.statements.len);
    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(ast.Infix.plus, expr.kind.infix.operator);
}

test "parser: prefix expression" {
    var lexer = Lexer.init("-42");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(Prefix.minus, expr.kind.prefix.operator);
}

test "parser: list literal" {
    var lexer = Lexer.init("[1, 2, 3]");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(@as(usize, 3), expr.kind.list.len);
}

test "parser: lambda expression" {
    var lexer = Lexer.init("|x| x + 1");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(@as(usize, 1), expr.kind.function.parameters.len);
}

test "parser: if expression" {
    var lexer = Lexer.init("if x { 1 } else { 2 }");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expect(expr.kind.@"if".alternative != null);
}

test "parser: let binding" {
    var lexer = Lexer.init("let x = 42");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqualStrings("x", expr.kind.let.name.kind.identifier);
}

test "parser: pipe chain" {
    var lexer = Lexer.init("x |> f |> g");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(@as(usize, 2), expr.kind.function_thread.functions.len);
}

test "parser: function composition" {
    var lexer = Lexer.init("f >> g >> h");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(@as(usize, 3), expr.kind.function_composition.len);
}

test "parser: match expression" {
    var lexer = Lexer.init("match x { 1 { a } _ { b } }");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(@as(usize, 2), expr.kind.match.cases.len);
}

test "parser: range expression" {
    var lexer = Lexer.init("1..10");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqualStrings("1", expr.kind.exclusive_range.from.kind.integer);
}

test "parser: dictionary" {
    var lexer = Lexer.init("#{a: 1, b: 2}");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const expr = program.statements[0].kind.expression;
    try testing.expectEqual(@as(usize, 2), expr.kind.dictionary.len);
}

test "parser: section" {
    var lexer = Lexer.init("input: 42");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    const section = program.statements[0].kind.section;
    try testing.expectEqualStrings("input", section.name);
}

test "parser: trailing comment" {
    var lexer = Lexer.init("let x = 1 // comment");
    var parser = Parser.init(testing.allocator, &lexer);
    var program = try parser.parse();
    defer program.deinit(testing.allocator);

    try testing.expect(program.statements[0].trailing_comment != null);
}
