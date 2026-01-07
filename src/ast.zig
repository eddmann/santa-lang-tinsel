const std = @import("std");
const token = @import("token.zig");
const Location = token.Location;

pub const Program = struct {
    statements: []Statement,
    source: Location,

    pub fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        for (self.statements) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.statements);
    }
};

pub const Attribute = struct {
    name: []const u8,
    source: Location,
};

pub const Statement = struct {
    kind: StatementKind,
    source: Location,
    preceded_by_blank_line: bool,
    trailing_comment: ?[]const u8,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        self.kind.deinit(allocator);
        if (self.trailing_comment) |comment| {
            allocator.free(comment);
        }
    }
};

pub const StatementKind = union(enum) {
    @"return": *Expression,
    @"break": *Expression,
    comment: []const u8,
    section: Section,
    expression: *Expression,
    block: []Statement,

    pub fn deinit(self: *StatementKind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .@"return" => |expr| {
                expr.deinit(allocator);
                allocator.destroy(expr);
            },
            .@"break" => |expr| {
                expr.deinit(allocator);
                allocator.destroy(expr);
            },
            .comment => |c| allocator.free(c),
            .section => |*s| s.deinit(allocator),
            .expression => |expr| {
                expr.deinit(allocator);
                allocator.destroy(expr);
            },
            .block => |stmts| {
                for (stmts) |*stmt| {
                    stmt.deinit(allocator);
                }
                allocator.free(stmts);
            },
        }
    }
};

pub const Section = struct {
    name: []const u8,
    body: *Program,
    attributes: []Attribute,

    pub fn deinit(self: *Section, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.body.deinit(allocator);
        allocator.destroy(self.body);
        for (self.attributes) |attr| {
            allocator.free(attr.name);
        }
        allocator.free(self.attributes);
    }
};

pub const MatchCase = struct {
    pattern: *Expression,
    guard: ?*Expression,
    consequence: *Statement,
    trailing_comment: ?[]const u8,

    pub fn deinit(self: *MatchCase, allocator: std.mem.Allocator) void {
        self.pattern.deinit(allocator);
        allocator.destroy(self.pattern);
        if (self.guard) |g| {
            g.deinit(allocator);
            allocator.destroy(g);
        }
        self.consequence.deinit(allocator);
        allocator.destroy(self.consequence);
        if (self.trailing_comment) |c| {
            allocator.free(c);
        }
    }
};

pub const Prefix = enum {
    bang,
    minus,

    pub fn symbol(self: Prefix) []const u8 {
        return switch (self) {
            .bang => "!",
            .minus => "-",
        };
    }
};

pub const Infix = union(enum) {
    plus,
    minus,
    asterisk,
    slash,
    modulo,
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    @"or",
    @"and",
    call: *Expression, // backtick operator

    pub fn symbol(self: Infix) []const u8 {
        return switch (self) {
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
            .call => "`",
        };
    }

    pub fn deinit(self: *Infix, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .call => |expr| {
                expr.deinit(allocator);
                allocator.destroy(expr);
            },
            else => {},
        }
    }
};

pub const DictEntry = struct {
    key: *Expression,
    value: *Expression,

    pub fn deinit(self: *DictEntry, allocator: std.mem.Allocator) void {
        self.key.deinit(allocator);
        allocator.destroy(self.key);
        self.value.deinit(allocator);
        allocator.destroy(self.value);
    }
};

pub const Expression = struct {
    kind: ExpressionKind,
    source: Location,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        self.kind.deinit(allocator);
    }
};

pub const ExpressionKind = union(enum) {
    // Literals
    integer: []const u8,
    decimal: []const u8,
    string: []const u8,
    boolean: bool,
    nil,
    placeholder,

    // Identifiers
    identifier: []const u8,
    rest_identifier: []const u8,

    // Bindings
    let: struct { name: *Expression, value: *Expression },
    mutable_let: struct { name: *Expression, value: *Expression },
    assign: struct { name: *Expression, value: *Expression },

    // Collections
    list: []*Expression,
    set: []*Expression,
    dictionary: []DictEntry,

    // Ranges
    inclusive_range: struct { from: *Expression, to: *Expression },
    exclusive_range: struct { from: *Expression, until: *Expression },
    unbounded_range: struct { from: *Expression },

    // Functions
    function: struct { parameters: []*Expression, body: *Statement },
    call: struct { function: *Expression, arguments: []*Expression },
    function_thread: struct { initial: *Expression, functions: []*Expression },
    function_composition: []*Expression,

    // Operators
    prefix: struct { operator: Prefix, right: *Expression },
    infix: struct { operator: Infix, left: *Expression, right: *Expression },
    operator_ref: []const u8, // operator used as first-class value, e.g., sort(<)

    // Control flow
    @"if": struct {
        condition: *Expression,
        consequence: *Statement,
        alternative: ?*Statement,
    },
    match: struct { subject: *Expression, cases: []MatchCase },

    // Index
    index: struct { left: *Expression, index_expr: *Expression },

    // Spread
    spread: *Expression,

    // Patterns (for destructuring)
    identifier_list_pattern: []*Expression,
    list_match_pattern: []*Expression,
    identifier_dict_pattern: []*Expression,
    dict_match_pattern: []*Expression,
    dict_entry_pattern: struct { key: *Expression, value: *Expression },

    pub fn deinit(self: *ExpressionKind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .integer, .decimal, .string => |s| allocator.free(s),
            .identifier, .rest_identifier, .operator_ref => |s| allocator.free(s),
            .boolean, .nil, .placeholder => {},

            .let => |*binding| {
                binding.name.deinit(allocator);
                allocator.destroy(binding.name);
                binding.value.deinit(allocator);
                allocator.destroy(binding.value);
            },
            .mutable_let => |*binding| {
                binding.name.deinit(allocator);
                allocator.destroy(binding.name);
                binding.value.deinit(allocator);
                allocator.destroy(binding.value);
            },
            .assign => |*binding| {
                binding.name.deinit(allocator);
                allocator.destroy(binding.name);
                binding.value.deinit(allocator);
                allocator.destroy(binding.value);
            },

            .list, .set => |exprs| {
                for (exprs) |expr| {
                    expr.deinit(allocator);
                    allocator.destroy(expr);
                }
                allocator.free(exprs);
            },

            .dictionary => |entries| {
                for (entries) |*entry| {
                    entry.deinit(allocator);
                }
                allocator.free(entries);
            },

            .inclusive_range => |*r| {
                r.from.deinit(allocator);
                allocator.destroy(r.from);
                r.to.deinit(allocator);
                allocator.destroy(r.to);
            },

            .exclusive_range => |*r| {
                r.from.deinit(allocator);
                allocator.destroy(r.from);
                r.until.deinit(allocator);
                allocator.destroy(r.until);
            },

            .unbounded_range => |*r| {
                r.from.deinit(allocator);
                allocator.destroy(r.from);
            },

            .function => |*f| {
                for (f.parameters) |p| {
                    p.deinit(allocator);
                    allocator.destroy(p);
                }
                allocator.free(f.parameters);
                f.body.deinit(allocator);
                allocator.destroy(f.body);
            },

            .call => |*c| {
                c.function.deinit(allocator);
                allocator.destroy(c.function);
                for (c.arguments) |arg| {
                    arg.deinit(allocator);
                    allocator.destroy(arg);
                }
                allocator.free(c.arguments);
            },

            .function_thread => |*ft| {
                ft.initial.deinit(allocator);
                allocator.destroy(ft.initial);
                for (ft.functions) |f| {
                    f.deinit(allocator);
                    allocator.destroy(f);
                }
                allocator.free(ft.functions);
            },

            .function_composition => |funcs| {
                for (funcs) |f| {
                    f.deinit(allocator);
                    allocator.destroy(f);
                }
                allocator.free(funcs);
            },

            .prefix => |*p| {
                p.right.deinit(allocator);
                allocator.destroy(p.right);
            },

            .infix => |*i| {
                i.operator.deinit(allocator);
                i.left.deinit(allocator);
                allocator.destroy(i.left);
                i.right.deinit(allocator);
                allocator.destroy(i.right);
            },

            .@"if" => |*if_expr| {
                if_expr.condition.deinit(allocator);
                allocator.destroy(if_expr.condition);
                if_expr.consequence.deinit(allocator);
                allocator.destroy(if_expr.consequence);
                if (if_expr.alternative) |alt| {
                    alt.deinit(allocator);
                    allocator.destroy(alt);
                }
            },

            .match => |*m| {
                m.subject.deinit(allocator);
                allocator.destroy(m.subject);
                for (m.cases) |*c| {
                    c.deinit(allocator);
                }
                allocator.free(m.cases);
            },

            .index => |*idx| {
                idx.left.deinit(allocator);
                allocator.destroy(idx.left);
                idx.index_expr.deinit(allocator);
                allocator.destroy(idx.index_expr);
            },

            .spread => |expr| {
                expr.deinit(allocator);
                allocator.destroy(expr);
            },

            .identifier_list_pattern, .list_match_pattern, .identifier_dict_pattern, .dict_match_pattern => |exprs| {
                for (exprs) |expr| {
                    expr.deinit(allocator);
                    allocator.destroy(expr);
                }
                allocator.free(exprs);
            },

            .dict_entry_pattern => |*dep| {
                dep.key.deinit(allocator);
                allocator.destroy(dep.key);
                dep.value.deinit(allocator);
                allocator.destroy(dep.value);
            },
        }
    }
};
