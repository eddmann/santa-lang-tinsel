const std = @import("std");
const ast = @import("ast.zig");
const doc = @import("doc.zig");
const Doc = doc.Doc;
const DocBuilder = doc.DocBuilder;
const Program = ast.Program;
const Statement = ast.Statement;
const StatementKind = ast.StatementKind;
const Expression = ast.Expression;
const ExpressionKind = ast.ExpressionKind;
const MatchCase = ast.MatchCase;
const DictEntry = ast.DictEntry;
const Prefix = ast.Prefix;
const Infix = ast.Infix;

/// Standard indentation level in spaces.
const INDENT_SIZE: usize = 2;

/// Error type for builder functions (needed for recursive function error set resolution)
pub const BuildError = std.mem.Allocator.Error;

/// Precedence levels for parenthesization decisions
const Precedence = enum(u8) {
    lowest = 0,
    and_or,
    equals,
    less_greater,
    composition,
    sum,
    product,
};

pub fn buildProgram(builder: *DocBuilder, program: *const Program) BuildError!*const Doc {
    if (program.statements.len == 0) {
        return builder.nil();
    }

    var parts: std.ArrayList(*const Doc) = .empty;
    const parts_alloc = builder.arena.allocator();

    for (program.statements, 0..) |*stmt, i| {
        if (i > 0) {
            // Always blank line between top-level statements
            try parts.append(parts_alloc, try builder.hardLine());
            try parts.append(parts_alloc, try builder.hardLine());
        }
        try parts.append(parts_alloc, try buildStatement(builder, stmt, true));

        // Emit trailing comment if present
        if (stmt.trailing_comment) |comment| {
            const comment_parts = try builder.arena.allocator().alloc(*const Doc, 2);
            comment_parts[0] = try builder.text(" ");
            comment_parts[1] = try builder.text(comment);
            try parts.append(parts_alloc, try builder.concat(comment_parts));
        }
    }
    try parts.append(parts_alloc, try builder.hardLine());

    return builder.concat(try parts.toOwnedSlice(parts_alloc));
}

fn buildStatements(builder: *DocBuilder, statements: []const Statement) BuildError!*const Doc {
    if (statements.len == 0) {
        return builder.nil();
    }

    const len = statements.len;
    var parts: std.ArrayList(*const Doc) = .empty;
    const parts_alloc = builder.arena.allocator();

    // Find index of last non-comment statement before implicit return
    var semicolon_index: ?usize = null;
    if (len >= 2) {
        const last = &statements[len - 1];
        const has_implicit_return = switch (last.kind) {
            .expression => |expr| switch (expr.kind) {
                .let, .mutable_let => false,
                else => true,
            },
            else => false,
        };

        if (has_implicit_return) {
            // Find last non-comment statement before the return
            var idx: usize = len - 2;
            while (true) : (idx -|= 1) {
                if (statements[idx].kind != .comment) {
                    semicolon_index = idx;
                    break;
                }
                if (idx == 0) break;
            }
        }
    }

    for (statements, 0..) |*stmt, i| {
        if (i > 0) {
            // Preserve user blank lines from source, or add for implicit returns
            const needs_blank = stmt.preceded_by_blank_line or blk: {
                if (i == len - 1 and len > 1) {
                    break :blk switch (stmt.kind) {
                        .expression => |expr| switch (expr.kind) {
                            .let, .mutable_let => false,
                            else => true,
                        },
                        .@"return" => |expr| isMultilineExpression(expr),
                        else => false,
                    };
                }
                break :blk false;
            };

            if (needs_blank) {
                try parts.append(parts_alloc, try builder.blankLine());
                try parts.append(parts_alloc, try builder.hardLine());
            } else {
                try parts.append(parts_alloc, try builder.hardLine());
            }
        }

        try parts.append(parts_alloc, try buildStatement(builder, stmt, false));

        if (semicolon_index == i) {
            try parts.append(parts_alloc, try builder.text(";"));
        }

        // Emit trailing comment if present
        if (stmt.trailing_comment) |comment| {
            const comment_parts = try builder.arena.allocator().alloc(*const Doc, 2);
            comment_parts[0] = try builder.text(" ");
            comment_parts[1] = try builder.text(comment);
            try parts.append(parts_alloc, try builder.concat(comment_parts));
        }
    }

    return builder.concat(try parts.toOwnedSlice(parts_alloc));
}

fn buildStatement(builder: *DocBuilder, stmt: *const Statement, is_top_level: bool) BuildError!*const Doc {
    return switch (stmt.kind) {
        .@"return" => |expr| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 2);
            p[0] = try builder.text("return ");
            p[1] = try buildExpression(builder, expr);
            break :blk builder.concat(p);
        },
        .@"break" => |expr| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 2);
            p[0] = try builder.text("break ");
            p[1] = try buildExpression(builder, expr);
            break :blk builder.concat(p);
        },
        .comment => |text| builder.text(text),
        .section => |section| try buildSection(builder, &section, is_top_level),
        .expression => |expr| buildExpression(builder, expr),
        .block => |stmts| blk: {
            if (stmts.len == 0) {
                break :blk builder.text("{}");
            }

            const p = try builder.arena.allocator().alloc(*const Doc, 4);
            p[0] = try builder.text("{");
            const inner_parts = try builder.arena.allocator().alloc(*const Doc, 2);
            inner_parts[0] = try builder.hardLine();
            inner_parts[1] = try buildStatements(builder, stmts);
            p[1] = try builder.nest(INDENT_SIZE, try builder.concat(inner_parts));
            p[2] = try builder.hardLine();
            p[3] = try builder.text("}");
            break :blk builder.concat(p);
        },
    };
}

fn buildSection(builder: *DocBuilder, section: *const ast.Section, is_top_level: bool) BuildError!*const Doc {
    var parts: std.ArrayList(*const Doc) = .empty;
    const parts_alloc = builder.arena.allocator();

    // Attributes
    for (section.attributes) |attr| {
        try parts.append(parts_alloc, try builder.text("@"));
        try parts.append(parts_alloc, try builder.text(attr.name));
        try parts.append(parts_alloc, try builder.hardLine());
    }

    // Section name
    try parts.append(parts_alloc, try builder.text(section.name));
    try parts.append(parts_alloc, try builder.text(": "));

    const always_braces = is_top_level and (std.mem.eql(u8, section.name, "part_one") or std.mem.eql(u8, section.name, "part_two"));

    // Check if we can inline the body
    if (!always_braces and section.body.statements.len == 1) {
        const first_stmt = &section.body.statements[0];
        if (first_stmt.kind == .expression) {
            const expr = first_stmt.kind.expression;
            if (!containsBlockLambda(expr)) {
                try parts.append(parts_alloc, try buildExpression(builder, expr));
                return builder.concat(try parts.toOwnedSlice(parts_alloc));
            }
        }
    }

    // Build block form
    try parts.append(parts_alloc, try builder.text("{"));
    const inner_parts = try builder.arena.allocator().alloc(*const Doc, 2);
    inner_parts[0] = try builder.hardLine();
    inner_parts[1] = try buildStatements(builder, section.body.statements);
    try parts.append(parts_alloc, try builder.nest(INDENT_SIZE, try builder.concat(inner_parts)));
    try parts.append(parts_alloc, try builder.hardLine());
    try parts.append(parts_alloc, try builder.text("}"));

    return builder.concat(try parts.toOwnedSlice(parts_alloc));
}

fn buildExpression(builder: *DocBuilder, expr: *const Expression) BuildError!*const Doc {
    return switch (expr.kind) {
        // Literals
        .integer => |value| builder.text(value),
        .decimal => |value| builder.text(value),
        .string => |value| buildString(builder, value),
        .boolean => |value| builder.text(if (value) "true" else "false"),
        .nil => builder.text("nil"),
        .placeholder => builder.text("_"),

        // Identifiers
        .identifier => |name| builder.text(name),
        .rest_identifier => |name| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 2);
            p[0] = try builder.text("..");
            p[1] = try builder.text(name);
            break :blk builder.concat(p);
        },

        // Bindings
        .let => |binding| buildLet(builder, binding.name, binding.value, false),
        .mutable_let => |binding| buildLet(builder, binding.name, binding.value, true),
        .assign => |binding| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = try buildExpression(builder, binding.name);
            p[1] = try builder.text(" = ");
            p[2] = try buildExpression(builder, binding.value);
            break :blk builder.concat(p);
        },

        // Collections
        .list => |elements| buildCollection(builder, "[", elements, "]"),
        .set => |elements| buildCollection(builder, "{", elements, "}"),
        .dictionary => |entries| buildDictionary(builder, entries),

        // Ranges
        .inclusive_range => |r| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = try buildExpression(builder, r.from);
            p[1] = try builder.text("..=");
            p[2] = try buildExpression(builder, r.to);
            break :blk builder.concat(p);
        },
        .exclusive_range => |r| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = try buildExpression(builder, r.from);
            p[1] = try builder.text("..");
            p[2] = try buildExpression(builder, r.until);
            break :blk builder.concat(p);
        },
        .unbounded_range => |r| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 2);
            p[0] = try buildExpression(builder, r.from);
            p[1] = try builder.text("..");
            break :blk builder.concat(p);
        },

        // Functions
        .function => |f| buildLambda(builder, f.parameters, f.body),
        .call => |c| buildCall(builder, c.function, c.arguments),

        // Operators
        .prefix => |p| buildPrefixExpr(builder, p.operator, p.right),
        .infix => |i| buildInfixExpr(builder, i.operator, i.left, i.right),

        // Control flow
        .@"if" => |if_expr| buildIf(builder, if_expr.condition, if_expr.consequence, if_expr.alternative),
        .match => |m| buildMatch(builder, m.subject, m.cases),

        // Functional operations
        .function_thread => |ft| buildChain(builder, ft.initial, ft.functions, "|>"),
        .function_composition => |funcs| buildComposition(builder, funcs),

        // Other
        .index => |idx| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 4);
            p[0] = try buildExpression(builder, idx.left);
            p[1] = try builder.text("[");
            p[2] = try buildExpression(builder, idx.index_expr);
            p[3] = try builder.text("]");
            break :blk builder.concat(p);
        },
        .spread => |inner| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 2);
            p[0] = try builder.text("..");
            p[1] = try buildExpression(builder, inner);
            break :blk builder.concat(p);
        },
        .identifier_list_pattern, .list_match_pattern => |elements| buildPattern(builder, elements),
        .identifier_dict_pattern, .dict_match_pattern => |elements| buildDictionaryPattern(builder, elements),
        .dict_entry_pattern => |dep| blk: {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = try buildExpression(builder, dep.key);
            p[1] = try builder.text(": ");
            p[2] = try buildExpression(builder, dep.value);
            break :blk builder.concat(p);
        },
    };
}

fn buildLet(builder: *DocBuilder, name: *const Expression, value: *const Expression, is_mutable: bool) BuildError!*const Doc {
    const prefix = if (is_mutable) "let mut " else "let ";
    const p = try builder.arena.allocator().alloc(*const Doc, 3);
    p[0] = try builder.text(prefix);
    p[1] = try buildExpression(builder, name);
    p[2] = try builder.text(" = ");

    const prefix_doc = try builder.concat(p);
    const value_doc = try buildExpression(builder, value);

    const final = try builder.arena.allocator().alloc(*const Doc, 2);
    final[0] = prefix_doc;
    final[1] = value_doc;
    return builder.concat(final);
}

fn buildCollection(builder: *DocBuilder, open: []const u8, elements: []*Expression, close: []const u8) BuildError!*const Doc {
    if (elements.len == 0) {
        const p = try builder.arena.allocator().alloc(*const Doc, 2);
        p[0] = try builder.text(open);
        p[1] = try builder.text(close);
        return builder.concat(p);
    }

    const docs = try builder.arena.allocator().alloc(*const Doc, elements.len);
    for (elements, 0..) |elem, i| {
        docs[i] = try buildExpression(builder, elem);
    }

    return builder.bracketed(open, docs, close, false);
}

fn buildDictionary(builder: *DocBuilder, entries: []const DictEntry) BuildError!*const Doc {
    if (entries.len == 0) {
        return builder.text("#{}");
    }

    const docs = try builder.arena.allocator().alloc(*const Doc, entries.len);
    for (entries, 0..) |entry, i| {
        // Check for shorthand syntax: if key is a string and value is an identifier with same name
        const use_shorthand = blk: {
            if (entry.key.kind == .string and entry.value.kind == .identifier) {
                if (std.mem.eql(u8, entry.key.kind.string, entry.value.kind.identifier)) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (use_shorthand) {
            docs[i] = try buildExpression(builder, entry.value);
        } else {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = try buildExpression(builder, entry.key);
            p[1] = try builder.text(": ");
            p[2] = try buildExpression(builder, entry.value);
            docs[i] = try builder.concat(p);
        }
    }

    const p = try builder.arena.allocator().alloc(*const Doc, 2);
    p[0] = try builder.text("#");
    p[1] = try builder.bracketed("{", docs, "}", false);
    return builder.concat(p);
}

fn buildPattern(builder: *DocBuilder, elements: []*Expression) BuildError!*const Doc {
    const docs = try builder.arena.allocator().alloc(*const Doc, elements.len);
    for (elements, 0..) |elem, i| {
        docs[i] = try buildExpression(builder, elem);
    }

    const sep = try builder.text(", ");
    const joined = try builder.join(docs, sep);

    const p = try builder.arena.allocator().alloc(*const Doc, 3);
    p[0] = try builder.text("[");
    p[1] = joined;
    p[2] = try builder.text("]");
    return builder.concat(p);
}

fn buildDictionaryPattern(builder: *DocBuilder, elements: []*Expression) BuildError!*const Doc {
    const docs = try builder.arena.allocator().alloc(*const Doc, elements.len);
    for (elements, 0..) |elem, i| {
        docs[i] = try buildExpression(builder, elem);
    }

    const sep = try builder.text(", ");
    const joined = try builder.join(docs, sep);

    const p = try builder.arena.allocator().alloc(*const Doc, 3);
    p[0] = try builder.text("#{");
    p[1] = joined;
    p[2] = try builder.text("}");
    return builder.concat(p);
}

fn buildPrefixExpr(builder: *DocBuilder, operator: Prefix, right: *const Expression) BuildError!*const Doc {
    const right_doc = try buildExpression(builder, right);
    const needs_parens = switch (right.kind) {
        .infix, .function_thread, .function_composition => true,
        else => false,
    };

    if (needs_parens) {
        const p = try builder.arena.allocator().alloc(*const Doc, 4);
        p[0] = try builder.text(operator.symbol());
        p[1] = try builder.text("(");
        p[2] = right_doc;
        p[3] = try builder.text(")");
        return builder.concat(p);
    } else {
        const p = try builder.arena.allocator().alloc(*const Doc, 2);
        p[0] = try builder.text(operator.symbol());
        p[1] = right_doc;
        return builder.concat(p);
    }
}

fn buildInfixExpr(builder: *DocBuilder, operator: Infix, left: *const Expression, right: *const Expression) BuildError!*const Doc {
    const op_prec = infixPrecedence(operator);
    const left_doc = try buildLeftExprWithParens(builder, left, op_prec);
    const right_doc = try buildRightExprWithParens(builder, right, op_prec);

    const op_str = switch (operator) {
        .plus => "+",
        .minus => "-",
        .asterisk => "*",
        .slash => "/",
        .modulo => "%",
        .equal => "==",
        .not_equal => "!=",
        .less_than => "<",
        .less_equal => "<=",
        .greater_than => ">",
        .greater_equal => ">=",
        .@"or" => "||",
        .@"and" => "&&",
        .call => |ident| {
            const p = try builder.arena.allocator().alloc(*const Doc, 7);
            p[0] = left_doc;
            p[1] = try builder.text(" `");
            p[2] = try buildExpression(builder, ident);
            p[3] = try builder.text("` ");
            p[4] = right_doc;
            return builder.group(try builder.concat(p[0..5]));
        },
    };

    const p = try builder.arena.allocator().alloc(*const Doc, 5);
    p[0] = left_doc;
    p[1] = try builder.text(" ");
    p[2] = try builder.text(op_str);
    p[3] = try builder.text(" ");
    p[4] = right_doc;
    return builder.group(try builder.concat(p));
}

fn buildLeftExprWithParens(builder: *DocBuilder, expr: *const Expression, parent_prec: Precedence) BuildError!*const Doc {
    const expr_prec = expressionPrecedence(expr);
    const doc_node = try buildExpression(builder, expr);

    if (@intFromEnum(expr_prec) < @intFromEnum(parent_prec) and expr_prec != .lowest) {
        const p = try builder.arena.allocator().alloc(*const Doc, 3);
        p[0] = try builder.text("(");
        p[1] = doc_node;
        p[2] = try builder.text(")");
        return builder.concat(p);
    }
    return doc_node;
}

fn buildRightExprWithParens(builder: *DocBuilder, expr: *const Expression, parent_prec: Precedence) BuildError!*const Doc {
    const expr_prec = expressionPrecedence(expr);
    const doc_node = try buildExpression(builder, expr);

    // For left-associative operators, any same-precedence expression on the right
    // needs parentheses to preserve the original grouping.
    const needs_parens = expr_prec != .lowest and @intFromEnum(expr_prec) <= @intFromEnum(parent_prec);

    if (needs_parens) {
        const p = try builder.arena.allocator().alloc(*const Doc, 3);
        p[0] = try builder.text("(");
        p[1] = doc_node;
        p[2] = try builder.text(")");
        return builder.concat(p);
    }
    return doc_node;
}

fn buildCall(builder: *DocBuilder, function: *const Expression, arguments: []*Expression) BuildError!*const Doc {
    if (arguments.len == 0) {
        const p = try builder.arena.allocator().alloc(*const Doc, 2);
        p[0] = try buildExpression(builder, function);
        p[1] = try builder.text("()");
        return builder.concat(p);
    }

    // Check for trailing closure
    const trailing = extractTrailingClosure(arguments);

    if (trailing == null) {
        // Regular call
        const args = try builder.arena.allocator().alloc(*const Doc, arguments.len);
        for (arguments, 0..) |arg, i| {
            args[i] = try buildExpression(builder, arg);
        }
        const p = try builder.arena.allocator().alloc(*const Doc, 2);
        p[0] = try buildExpression(builder, function);
        p[1] = try builder.bracketed("(", args, ")", false);
        return builder.concat(p);
    }

    const tc = trailing.?;
    const func = try buildExpression(builder, function);
    const block_lambda = try buildLambdaWithBlock(builder, tc.parameters, tc.body);

    // Multi-statement lambdas always use trailing syntax
    if (tc.is_multi_statement) {
        if (tc.is_only_argument) {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = func;
            p[1] = try builder.text(" ");
            p[2] = block_lambda;
            return builder.concat(p);
        } else {
            const other_args = try builder.arena.allocator().alloc(*const Doc, arguments.len - 1);
            for (arguments[0 .. arguments.len - 1], 0..) |arg, i| {
                other_args[i] = try buildExpression(builder, arg);
            }
            const p = try builder.arena.allocator().alloc(*const Doc, 4);
            p[0] = func;
            p[1] = try builder.bracketed("(", other_args, ")", false);
            p[2] = try builder.text(" ");
            p[3] = block_lambda;
            return builder.concat(p);
        }
    }

    // Single-statement: use trailing with block if line would exceed width
    const inline_lambda = try buildLambda(builder, tc.parameters, tc.body);

    const inline_doc = if (tc.is_only_argument) blk: {
        const p = try builder.arena.allocator().alloc(*const Doc, 4);
        p[0] = try buildExpression(builder, function);
        p[1] = try builder.text("(");
        p[2] = inline_lambda;
        p[3] = try builder.text(")");
        break :blk try builder.concat(p);
    } else blk: {
        const all_args = try builder.arena.allocator().alloc(*const Doc, arguments.len);
        for (arguments, 0..) |arg, i| {
            all_args[i] = try buildExpression(builder, arg);
        }
        const p = try builder.arena.allocator().alloc(*const Doc, 2);
        p[0] = try buildExpression(builder, function);
        p[1] = try builder.bracketed("(", all_args, ")", false);
        break :blk try builder.concat(p);
    };

    const trailing_doc = if (tc.is_only_argument) blk: {
        const p = try builder.arena.allocator().alloc(*const Doc, 3);
        p[0] = try buildExpression(builder, function);
        p[1] = try builder.text(" ");
        p[2] = block_lambda;
        break :blk try builder.concat(p);
    } else blk: {
        const other_args = try builder.arena.allocator().alloc(*const Doc, arguments.len - 1);
        for (arguments[0 .. arguments.len - 1], 0..) |arg, i| {
            other_args[i] = try buildExpression(builder, arg);
        }
        const p = try builder.arena.allocator().alloc(*const Doc, 4);
        p[0] = try buildExpression(builder, function);
        p[1] = try builder.bracketed("(", other_args, ")", false);
        p[2] = try builder.text(" ");
        p[3] = block_lambda;
        break :blk try builder.concat(p);
    };

    return builder.group(try builder.ifBreak(trailing_doc, inline_doc));
}

const TrailingClosure = struct {
    parameters: []*Expression,
    body: *const Statement,
    is_only_argument: bool,
    is_multi_statement: bool,
};

fn extractTrailingClosure(arguments: []*Expression) ?TrailingClosure {
    if (arguments.len == 0) return null;

    const last_arg = arguments[arguments.len - 1];
    if (last_arg.kind != .function) return null;

    const func = last_arg.kind.function;
    const is_multi = switch (func.body.kind) {
        .block => |stmts| stmts.len > 1,
        else => false,
    };

    return .{
        .parameters = func.parameters,
        .body = func.body,
        .is_only_argument = arguments.len == 1,
        .is_multi_statement = is_multi,
    };
}

fn buildChain(builder: *DocBuilder, initial: *const Expression, functions: []*Expression, op: []const u8) BuildError!*const Doc {
    // Special case: single-pipe chain with trailing block lambda
    if (functions.len == 1) {
        if (try buildCallForChain(builder, functions[0])) |call_doc| {
            const p = try builder.arena.allocator().alloc(*const Doc, 4);
            p[0] = try buildExpression(builder, initial);
            p[1] = try builder.text(" ");
            p[2] = try builder.text(op);
            p[3] = try builder.text(" ");

            const prefix = try builder.concat(p[0..4]);
            const final = try builder.arena.allocator().alloc(*const Doc, 2);
            final[0] = prefix;
            final[1] = call_doc;
            return builder.concat(final);
        }
    }

    const force_break = functions.len > 1;

    var chain: std.ArrayList(*const Doc) = .empty;
    const chain_alloc = builder.arena.allocator();
    for (functions, 0..) |f, i| {
        const is_last = i == functions.len - 1;

        // Lambdas that aren't the last element need block braces
        const f_doc = if (f.kind == .function and !is_last)
            try buildLambdaWithBlock(builder, f.kind.function.parameters, f.kind.function.body)
        else
            try buildExpression(builder, f);

        const line_doc = if (force_break) try builder.hardLine() else try builder.line();

        const op_parts = try builder.arena.allocator().alloc(*const Doc, 3);
        op_parts[0] = line_doc;
        op_parts[1] = try builder.text(op);
        op_parts[2] = try builder.text(" ");

        const parts = try builder.arena.allocator().alloc(*const Doc, 2);
        parts[0] = try builder.concat(op_parts);
        parts[1] = f_doc;
        try chain.append(chain_alloc, try builder.concat(parts));
    }

    const chain_doc = try builder.concat(try chain.toOwnedSlice(chain_alloc));
    const nested = try builder.nest(INDENT_SIZE, chain_doc);

    const p = try builder.arena.allocator().alloc(*const Doc, 2);
    p[0] = try buildExpression(builder, initial);
    p[1] = nested;
    const result_doc = try builder.concat(p);

    if (force_break) {
        return result_doc;
    }
    return builder.group(result_doc);
}

fn buildCallForChain(builder: *DocBuilder, expr: *const Expression) !?*const Doc {
    if (expr.kind != .call) return null;

    const call = expr.kind.call;
    const trailing = extractTrailingClosure(call.arguments) orelse return null;

    // Multi-statement lambdas always use trailing block syntax
    if (trailing.is_multi_statement) {
        const func = try buildExpression(builder, call.function);
        const block_lambda = try buildLambdaWithBlock(builder, trailing.parameters, trailing.body);

        if (trailing.is_only_argument) {
            const p = try builder.arena.allocator().alloc(*const Doc, 3);
            p[0] = func;
            p[1] = try builder.text(" ");
            p[2] = block_lambda;
            return builder.concat(p);
        } else {
            const other_args = try builder.arena.allocator().alloc(*const Doc, call.arguments.len - 1);
            for (call.arguments[0 .. call.arguments.len - 1], 0..) |arg, i| {
                other_args[i] = try buildExpression(builder, arg);
            }
            const p = try builder.arena.allocator().alloc(*const Doc, 4);
            p[0] = func;
            p[1] = try builder.bracketed("(", other_args, ")", false);
            p[2] = try builder.text(" ");
            p[3] = block_lambda;
            return builder.concat(p);
        }
    }

    // For single-statement lambdas, check if inline form would be short enough
    const func = try buildExpression(builder, call.function);
    const inline_lambda = try buildLambda(builder, trailing.parameters, trailing.body);
    const block_lambda = try buildLambdaWithBlock(builder, trailing.parameters, trailing.body);

    const inline_doc = if (trailing.is_only_argument) blk: {
        const p = try builder.arena.allocator().alloc(*const Doc, 4);
        p[0] = try buildExpression(builder, call.function);
        p[1] = try builder.text("(");
        p[2] = inline_lambda;
        p[3] = try builder.text(")");
        break :blk try builder.concat(p);
    } else blk: {
        const all_args = try builder.arena.allocator().alloc(*const Doc, call.arguments.len);
        for (call.arguments, 0..) |arg, i| {
            all_args[i] = try buildExpression(builder, arg);
        }
        const p = try builder.arena.allocator().alloc(*const Doc, 2);
        p[0] = try buildExpression(builder, call.function);
        p[1] = try builder.bracketed("(", all_args, ")", false);
        break :blk try builder.concat(p);
    };

    const trailing_doc = if (trailing.is_only_argument) blk: {
        const p = try builder.arena.allocator().alloc(*const Doc, 3);
        p[0] = func;
        p[1] = try builder.text(" ");
        p[2] = block_lambda;
        break :blk try builder.concat(p);
    } else blk: {
        const other_args = try builder.arena.allocator().alloc(*const Doc, call.arguments.len - 1);
        for (call.arguments[0 .. call.arguments.len - 1], 0..) |arg, i| {
            other_args[i] = try buildExpression(builder, arg);
        }
        const p = try builder.arena.allocator().alloc(*const Doc, 4);
        p[0] = func;
        p[1] = try builder.bracketed("(", other_args, ")", false);
        p[2] = try builder.text(" ");
        p[3] = block_lambda;
        break :blk try builder.concat(p);
    };

    return builder.group(try builder.ifBreak(trailing_doc, inline_doc));
}

fn buildComposition(builder: *DocBuilder, functions: []*Expression) BuildError!*const Doc {
    if (functions.len == 0) {
        return builder.nil();
    }

    const docs = try builder.arena.allocator().alloc(*const Doc, functions.len);
    for (functions, 0..) |f, i| {
        docs[i] = try buildExpression(builder, f);
    }

    // Build rest with >> prefix
    var rest: std.ArrayList(*const Doc) = .empty;
    const rest_alloc = builder.arena.allocator();
    for (docs[1..]) |d| {
        const parts = try builder.arena.allocator().alloc(*const Doc, 3);
        parts[0] = try builder.line();
        parts[1] = try builder.text(">> ");
        parts[2] = d;
        try rest.append(rest_alloc, try builder.concat(parts));
    }

    const rest_doc = try builder.concat(try rest.toOwnedSlice(rest_alloc));
    const nested = try builder.nest(INDENT_SIZE, rest_doc);

    const p = try builder.arena.allocator().alloc(*const Doc, 2);
    p[0] = docs[0];
    p[1] = nested;
    return builder.group(try builder.concat(p));
}

fn buildIf(builder: *DocBuilder, condition: *const Expression, consequence: *const Statement, alternative: ?*const Statement) BuildError!*const Doc {
    const inline_doc = try buildInlineIf(builder, condition, consequence, alternative);
    const multiline_doc = try buildMultilineIf(builder, condition, consequence, alternative);
    return builder.group(try builder.ifBreak(multiline_doc, inline_doc));
}

fn buildInlineIf(builder: *DocBuilder, condition: *const Expression, consequence: *const Statement, alternative: ?*const Statement) BuildError!*const Doc {
    var parts: std.ArrayList(*const Doc) = .empty;
    const parts_alloc = builder.arena.allocator();

    try parts.append(parts_alloc, try builder.text("if "));
    try parts.append(parts_alloc, try buildExpression(builder, condition));
    try parts.append(parts_alloc, try builder.text(" { "));
    try parts.append(parts_alloc, try buildInlineBody(builder, consequence));
    try parts.append(parts_alloc, try builder.text(" }"));

    if (alternative) |alt| {
        try parts.append(parts_alloc, try builder.text(" else { "));
        try parts.append(parts_alloc, try buildInlineBody(builder, alt));
        try parts.append(parts_alloc, try builder.text(" }"));
    }

    return builder.concat(try parts.toOwnedSlice(parts_alloc));
}

fn buildMultilineIf(builder: *DocBuilder, condition: *const Expression, consequence: *const Statement, alternative: ?*const Statement) BuildError!*const Doc {
    var parts: std.ArrayList(*const Doc) = .empty;
    const parts_alloc = builder.arena.allocator();

    try parts.append(parts_alloc, try builder.text("if "));
    try parts.append(parts_alloc, try buildExpression(builder, condition));
    try parts.append(parts_alloc, try builder.text(" "));
    try parts.append(parts_alloc, try buildBlockStatement(builder, consequence));

    if (alternative) |alt| {
        try parts.append(parts_alloc, try builder.text(" else "));
        try parts.append(parts_alloc, try buildBlockStatement(builder, alt));
    }

    return builder.concat(try parts.toOwnedSlice(parts_alloc));
}

fn buildInlineBody(builder: *DocBuilder, stmt: *const Statement) BuildError!*const Doc {
    return switch (stmt.kind) {
        .expression => |expr| buildExpression(builder, expr),
        .block => |stmts| {
            if (stmts.len == 1) {
                if (stmts[0].kind == .expression) {
                    return buildExpression(builder, stmts[0].kind.expression);
                }
            }
            return buildBlockStatement(builder, stmt);
        },
        else => buildBlockStatement(builder, stmt),
    };
}

fn buildBlockStatement(builder: *DocBuilder, stmt: *const Statement) BuildError!*const Doc {
    return switch (stmt.kind) {
        .block => buildStatement(builder, stmt, false),
        else => {
            const inner_parts = try builder.arena.allocator().alloc(*const Doc, 2);
            inner_parts[0] = try builder.hardLine();
            inner_parts[1] = try buildStatement(builder, stmt, false);

            const p = try builder.arena.allocator().alloc(*const Doc, 4);
            p[0] = try builder.text("{");
            p[1] = try builder.nest(INDENT_SIZE, try builder.concat(inner_parts));
            p[2] = try builder.hardLine();
            p[3] = try builder.text("}");
            return builder.concat(p);
        },
    };
}

fn buildMatch(builder: *DocBuilder, subject: *const Expression, cases: []const MatchCase) BuildError!*const Doc {
    var case_docs: std.ArrayList(*const Doc) = .empty;
    const case_docs_alloc = builder.arena.allocator();
    for (cases) |*c| {
        try case_docs.append(case_docs_alloc, try buildMatchCase(builder, c));
    }

    const inner_parts = try builder.arena.allocator().alloc(*const Doc, 2);
    inner_parts[0] = try builder.hardLine();
    inner_parts[1] = try builder.join(try case_docs.toOwnedSlice(case_docs_alloc), try builder.hardLine());

    const p = try builder.arena.allocator().alloc(*const Doc, 5);
    p[0] = try builder.text("match ");
    p[1] = try buildExpression(builder, subject);
    p[2] = try builder.text(" {");
    p[3] = try builder.nest(INDENT_SIZE, try builder.concat(inner_parts));
    p[4] = try builder.hardLine();

    const parts = try builder.arena.allocator().alloc(*const Doc, 2);
    parts[0] = try builder.concat(p);
    parts[1] = try builder.text("}");
    return builder.concat(parts);
}

fn buildMatchCase(builder: *DocBuilder, case: *const MatchCase) BuildError!*const Doc {
    var parts: std.ArrayList(*const Doc) = .empty;
    const parts_alloc = builder.arena.allocator();

    try parts.append(parts_alloc, try buildExpression(builder, case.pattern));

    if (case.guard) |guard| {
        try parts.append(parts_alloc, try builder.text(" if "));
        try parts.append(parts_alloc, try buildExpression(builder, guard));
    }

    if (isSimpleBody(case.consequence)) {
        try parts.append(parts_alloc, try builder.text(" { "));
        try parts.append(parts_alloc, try buildInlineBody(builder, case.consequence));
        try parts.append(parts_alloc, try builder.text(" }"));
    } else {
        try parts.append(parts_alloc, try builder.text(" "));
        try parts.append(parts_alloc, try buildBlockStatement(builder, case.consequence));
    }

    if (case.trailing_comment) |comment| {
        try parts.append(parts_alloc, try builder.text(" "));
        try parts.append(parts_alloc, try builder.text(comment));
    }

    return builder.concat(try parts.toOwnedSlice(parts_alloc));
}

fn buildLambda(builder: *DocBuilder, parameters: []*Expression, body: *const Statement) BuildError!*const Doc {
    const params_docs = try builder.arena.allocator().alloc(*const Doc, parameters.len);
    for (parameters, 0..) |p, i| {
        params_docs[i] = try buildExpression(builder, p);
    }
    const params_doc = try builder.join(params_docs, try builder.text(", "));

    const body_doc = switch (body.kind) {
        .block => |stmts| blk: {
            if (stmts.len == 1) {
                const first = &stmts[0];
                if (first.kind == .expression) {
                    const expr = first.kind.expression;
                    // Don't unwrap if body is set/dict or has pipe/composition
                    if (expr.kind == .set or expr.kind == .dictionary or hasPipeOrComposition(expr)) {
                        break :blk try buildBlockBody(builder, stmts);
                    }
                    break :blk try buildExpression(builder, expr);
                }
            }
            break :blk try buildBlockBody(builder, stmts);
        },
        .expression => |expr| try buildExpression(builder, expr),
        else => try buildStatement(builder, body, false),
    };

    const p = try builder.arena.allocator().alloc(*const Doc, 4);
    p[0] = try builder.text("|");
    p[1] = params_doc;
    p[2] = try builder.text("| ");
    p[3] = body_doc;
    return builder.concat(p);
}

fn buildLambdaWithBlock(builder: *DocBuilder, parameters: []*Expression, body: *const Statement) BuildError!*const Doc {
    const params_docs = try builder.arena.allocator().alloc(*const Doc, parameters.len);
    for (parameters, 0..) |p, i| {
        params_docs[i] = try buildExpression(builder, p);
    }
    const params_doc = try builder.join(params_docs, try builder.text(", "));

    const body_doc = switch (body.kind) {
        .block => |stmts| try buildBlockBody(builder, stmts),
        else => try buildBlockStatement(builder, body),
    };

    const p = try builder.arena.allocator().alloc(*const Doc, 4);
    p[0] = try builder.text("|");
    p[1] = params_doc;
    p[2] = try builder.text("| ");
    p[3] = body_doc;
    return builder.concat(p);
}

fn buildBlockBody(builder: *DocBuilder, stmts: []const Statement) BuildError!*const Doc {
    if (stmts.len == 0) {
        return builder.text("{}");
    }

    const inner_parts = try builder.arena.allocator().alloc(*const Doc, 2);
    inner_parts[0] = try builder.hardLine();
    inner_parts[1] = try buildStatements(builder, stmts);

    const p = try builder.arena.allocator().alloc(*const Doc, 4);
    p[0] = try builder.text("{");
    p[1] = try builder.nest(INDENT_SIZE, try builder.concat(inner_parts));
    p[2] = try builder.hardLine();
    p[3] = try builder.text("}");
    return builder.concat(p);
}

fn buildString(builder: *DocBuilder, value: []const u8) BuildError!*const Doc {
    const escaped = try escapeString(builder.arena.allocator(), value);
    var buf: [2048]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "\"{s}\"", .{escaped}) catch {
        // Fall back for very long strings
        const p = try builder.arena.allocator().alloc(*const Doc, 3);
        p[0] = try builder.text("\"");
        p[1] = try builder.text(escaped);
        p[2] = try builder.text("\"");
        return builder.concat(p);
    };
    return builder.text(try builder.arena.allocator().dupe(u8, formatted));
}

fn escapeString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var newline_count: usize = 0;
    for (s) |c| {
        if (c == '\n') newline_count += 1;
    }
    const is_multiline_content = newline_count > 3 or s.len > 50;

    var result: std.ArrayList(u8) = .empty;
    for (s) |c| {
        switch (c) {
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '"' => try result.appendSlice(allocator, "\\\""),
            '\n' => {
                if (is_multiline_content) {
                    try result.append(allocator, '\n');
                } else {
                    try result.appendSlice(allocator, "\\n");
                }
            },
            '\t' => try result.appendSlice(allocator, "\\t"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            0x08 => try result.appendSlice(allocator, "\\b"), // Backspace
            0x0C => try result.appendSlice(allocator, "\\f"), // Form feed
            else => try result.append(allocator, c),
        }
    }
    return result.toOwnedSlice(allocator);
}

fn infixPrecedence(op: Infix) Precedence {
    return switch (op) {
        .@"and", .@"or" => .and_or,
        .equal, .not_equal => .equals,
        .less_than, .less_equal, .greater_than, .greater_equal => .less_greater,
        .plus, .minus => .sum,
        .asterisk, .slash, .modulo, .call => .product,
    };
}

fn expressionPrecedence(expr: *const Expression) Precedence {
    return switch (expr.kind) {
        .infix => |i| infixPrecedence(i.operator),
        .function_thread, .function_composition => .composition,
        .inclusive_range, .exclusive_range, .unbounded_range => .composition,
        else => .lowest,
    };
}

fn hasPipeOrComposition(expr: *const Expression) bool {
    return switch (expr.kind) {
        .function_thread, .function_composition => true,
        else => false,
    };
}

fn isSimpleBody(stmt: *const Statement) bool {
    return switch (stmt.kind) {
        .expression => |expr| !containsBlockLambda(expr),
        .block => |stmts| {
            if (stmts.len == 1) {
                if (stmts[0].kind == .expression) {
                    return !containsBlockLambda(stmts[0].kind.expression);
                }
            }
            return false;
        },
        else => false,
    };
}

fn containsBlockLambda(expr: *const Expression) bool {
    return switch (expr.kind) {
        .function => |f| switch (f.body.kind) {
            .block => |stmts| stmts.len > 1 or blk: {
                for (stmts) |s| {
                    if (s.kind != .expression) break :blk true;
                }
                break :blk false;
            },
            else => false,
        },
        .call => |c| {
            if (containsBlockLambda(c.function)) return true;
            for (c.arguments) |arg| {
                if (containsBlockLambda(arg)) return true;
            }
            return false;
        },
        .function_thread => |ft| {
            if (containsBlockLambda(ft.initial)) return true;
            for (ft.functions) |f| {
                if (containsBlockLambda(f)) return true;
            }
            return false;
        },
        .function_composition => |funcs| {
            for (funcs) |f| {
                if (containsBlockLambda(f)) return true;
            }
            return false;
        },
        .infix => |i| containsBlockLambda(i.left) or containsBlockLambda(i.right),
        .prefix => |p| containsBlockLambda(p.right),
        .index => |idx| containsBlockLambda(idx.left) or containsBlockLambda(idx.index_expr),
        .list, .set => |elements| {
            for (elements) |e| {
                if (containsBlockLambda(e)) return true;
            }
            return false;
        },
        .dictionary => |entries| {
            for (entries) |e| {
                if (containsBlockLambda(e.key) or containsBlockLambda(e.value)) return true;
            }
            return false;
        },
        .@"if" => |if_expr| {
            if (containsBlockLambda(if_expr.condition)) return true;
            if (containsBlockLambdaInStmt(if_expr.consequence)) return true;
            if (if_expr.alternative) |alt| {
                if (containsBlockLambdaInStmt(alt)) return true;
            }
            return false;
        },
        .match => true,
        else => false,
    };
}

fn containsBlockLambdaInStmt(stmt: *const Statement) bool {
    return switch (stmt.kind) {
        .expression => |expr| containsBlockLambda(expr),
        .block => |stmts| {
            for (stmts) |s| {
                if (containsBlockLambdaInStmt(&s)) return true;
            }
            return false;
        },
        .@"return", .@"break" => |expr| containsBlockLambda(expr),
        .section => |s| {
            for (s.body.statements) |st| {
                if (containsBlockLambdaInStmt(&st)) return true;
            }
            return false;
        },
        .comment => false,
    };
}

fn isMultilineExpression(expr: *const Expression) bool {
    return switch (expr.kind) {
        .function_thread => |ft| ft.functions.len > 1,
        .function_composition => |funcs| funcs.len > 1,
        .match => true,
        .function => |f| switch (f.body.kind) {
            .block => |stmts| stmts.len > 1,
            else => false,
        },
        else => false,
    };
}

