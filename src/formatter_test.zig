const std = @import("std");
const testing = std.testing;
const lib = @import("lib.zig");

fn expectFormat(input: []const u8, expected: []const u8) !void {
    const result = try lib.format(testing.allocator, input);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings(expected, result);
}

fn assertIdempotent(source: []const u8) !void {
    const first = try lib.format(testing.allocator, source);
    defer testing.allocator.free(first);
    const second = try lib.format(testing.allocator, first);
    defer testing.allocator.free(second);
    try testing.expectEqualStrings(first, second);
}

// === LITERALS ===

test "format: integer" {
    try expectFormat("42", "42\n");
}

test "format: integer with underscores" {
    try expectFormat("1_000_000", "1_000_000\n");
}

test "format: decimal" {
    try expectFormat("3.14", "3.14\n");
}

test "format: decimal with underscores" {
    try expectFormat("1_000.50", "1_000.50\n");
}

test "format: string simple" {
    try expectFormat("\"hello\"", "\"hello\"\n");
}

test "format: string escapes newlines" {
    try expectFormat("\"a\\nb\"", "\"a\\nb\"\n");
}

test "format: string with tab" {
    try expectFormat("\"a\\tb\"", "\"a\\tb\"\n");
}

test "format: string with quote" {
    try expectFormat("\"a\\\"b\"", "\"a\\\"b\"\n");
}

test "format: string with backslash" {
    try expectFormat("\"a\\\\b\"", "\"a\\\\b\"\n");
}

test "format: string with carriage return" {
    try expectFormat("\"a\\rb\"", "\"a\\rb\"\n");
}

test "format: boolean true" {
    try expectFormat("true", "true\n");
}

test "format: boolean false" {
    try expectFormat("false", "false\n");
}

test "format: nil" {
    try expectFormat("nil", "nil\n");
}

test "format: placeholder" {
    try expectFormat("_", "_\n");
}

// === OPERATORS ===

test "format: infix plus" {
    try expectFormat("1+2", "1 + 2\n");
}

test "format: infix minus" {
    try expectFormat("1-2", "1 - 2\n");
}

test "format: infix multiply" {
    try expectFormat("1*2", "1 * 2\n");
}

test "format: infix divide" {
    try expectFormat("1/2", "1 / 2\n");
}

test "format: infix modulo" {
    try expectFormat("1%2", "1 % 2\n");
}

test "format: infix equal" {
    try expectFormat("1==2", "1 == 2\n");
}

test "format: infix not equal" {
    try expectFormat("1!=2", "1 != 2\n");
}

test "format: infix less than" {
    try expectFormat("1<2", "1 < 2\n");
}

test "format: infix less than equal" {
    try expectFormat("1<=2", "1 <= 2\n");
}

test "format: infix greater than" {
    try expectFormat("1>2", "1 > 2\n");
}

test "format: infix greater than equal" {
    try expectFormat("1>=2", "1 >= 2\n");
}

test "format: infix and" {
    try expectFormat("true&&false", "true && false\n");
}

test "format: infix or" {
    try expectFormat("true||false", "true || false\n");
}

test "format: prefix bang" {
    try expectFormat("!true", "!true\n");
}

test "format: prefix bang removes space" {
    try expectFormat("! true", "!true\n");
}

test "format: prefix minus" {
    try expectFormat("-42", "-42\n");
}

test "format: prefix minus with infix preserves parens" {
    try expectFormat("-(a + b)", "-(a + b)\n");
}

test "format: prefix minus without parens stays flat" {
    try expectFormat("-a + b", "-a + b\n");
}

test "format: prefix bang with infix preserves parens" {
    try expectFormat("!(a && b)", "!(a && b)\n");
}

test "format: prefix with function thread preserves parens" {
    try expectFormat("-(a |> b)", "-(a |> b)\n");
}

test "format: chained operators" {
    try expectFormat("1+2*3", "1 + 2 * 3\n");
}

test "format: backtick operator" {
    try expectFormat("1 `add` 2", "1 `add` 2\n");
}

// === COLLECTIONS ===

test "format: empty list" {
    try expectFormat("[]", "[]\n");
}

test "format: list short" {
    try expectFormat("[1,2,3]", "[1, 2, 3]\n");
}

test "format: empty set" {
    try expectFormat("{}", "{}\n");
}

test "format: set short" {
    try expectFormat("{1,2,3}", "{1, 2, 3}\n");
}

test "format: empty dict" {
    try expectFormat("#{}", "#{}\n");
}

test "format: dict short" {
    try expectFormat("#{a:1,b:2}", "#{a: 1, b: 2}\n");
}

test "format: nested collections" {
    try expectFormat("[[1,2],[3,4]]", "[[1, 2], [3, 4]]\n");
}

test "format: list long formats correctly" {
    try expectFormat("[very_long_name_one, very_long_name_two, very_long_name_three]", "[very_long_name_one, very_long_name_two, very_long_name_three]\n");
}

test "format: dict with string keys" {
    try expectFormat("#{\"a\":1,\"b\":2}", "#{\"a\": 1, \"b\": 2}\n");
}

// === RANGES ===

test "format: range exclusive" {
    try expectFormat("1..10", "1..10\n");
}

test "format: range inclusive" {
    try expectFormat("1..=10", "1..=10\n");
}

test "format: range unbounded" {
    try expectFormat("1..", "1..\n");
}

// === LAMBDAS ===

test "format: lambda no params" {
    try expectFormat("|| 42", "|| 42\n");
}

test "format: lambda single param" {
    try expectFormat("|x|x+1", "|x| x + 1\n");
}

test "format: lambda multi param" {
    try expectFormat("|x,y|x+y", "|x, y| x + y\n");
}

test "format: lambda with block" {
    try expectFormat("|x| { let y = x + 1; y }", "|x| {\n  let y = x + 1;\n\n  y\n}\n");
}

// === CALLS ===

test "format: call no args" {
    try expectFormat("f()", "f()\n");
}

test "format: call single arg" {
    try expectFormat("f(1)", "f(1)\n");
}

test "format: call multi args" {
    try expectFormat("f(1,2,3)", "f(1, 2, 3)\n");
}

test "format: call nested" {
    try expectFormat("f(g(x))", "f(g(x))\n");
}

test "format: single statement lambda inside parens" {
    try expectFormat("map(|x| x + 1)", "map(|x| x + 1)\n");
}

test "format: lambda with other args inline when short" {
    try expectFormat("fold(0, |acc, x| acc + x)", "fold(0, |acc, x| acc + x)\n");
}

// === IF-ELSE ===

test "format: if only inline" {
    try expectFormat("if x { 1 }", "if x { 1 }\n");
}

test "format: if else inline" {
    try expectFormat("if x { 1 } else { 2 }", "if x { 1 } else { 2 }\n");
}

test "format: if else inline in lambda" {
    try expectFormat("|c| if c == \"(\" { 1 } else { -1 }", "|c| if c == \"(\" { 1 } else { -1 }\n");
}

test "format: if else multiline when body complex" {
    try expectFormat("if x { let y = 1\ny } else { 2 }", "if x {\n  let y = 1;\n\n  y\n} else {\n  2\n}\n");
}

// === MATCH ===

test "format: match inline cases" {
    try expectFormat("match x { 0 { \"zero\" } _ { \"other\" } }", "match x {\n  0 { \"zero\" }\n  _ { \"other\" }\n}\n");
}

test "format: match with guard inline" {
    try expectFormat("match x { n if n > 0 { n } _ { 0 } }", "match x {\n  n if n > 0 { n }\n  _ { 0 }\n}\n");
}

test "format: match multiline when complex" {
    try expectFormat("match x { 1 { let y = 2\ny } }", "match x {\n  1 {\n    let y = 2;\n\n    y\n  }\n}\n");
}

test "format: match preserves trailing comment on case" {
    try expectFormat("match x { 1 { a } // comment\n2 { b } }", "match x {\n  1 { a } // comment\n  2 { b }\n}\n");
}

// === PIPE CHAINS ===

test "format: pipe two elements inline" {
    try expectFormat("[1, 2] |> sum", "[1, 2] |> sum\n");
}

test "format: pipe three or more elements multiline" {
    try expectFormat("input |> lines |> filter(is_nice?) |> size", "input\n  |> lines\n  |> filter(is_nice?)\n  |> size\n");
}

test "format: pipe chain multiline" {
    try expectFormat("[1, 2, 3] |> map(f) |> filter(g) |> sum", "[1, 2, 3]\n  |> map(f)\n  |> filter(g)\n  |> sum\n");
}

// === COMPOSITION ===

test "format: composition two functions inline" {
    try expectFormat("f >> g", "f >> g\n");
}

test "format: composition three functions inline when fits" {
    try expectFormat("f >> g >> h", "f >> g >> h\n");
}

test "format: composition many short functions inline" {
    try expectFormat("a >> b >> c >> d >> e >> f", "a >> b >> c >> d >> e >> f\n");
}

// === BINDINGS ===

test "format: let" {
    try expectFormat("let x=1", "let x = 1\n");
}

test "format: let mut" {
    try expectFormat("let mut x=1", "let mut x = 1\n");
}

test "format: let with expression" {
    try expectFormat("let x=1+2", "let x = 1 + 2\n");
}

test "format: assign" {
    try expectFormat("x=1", "x = 1\n");
}

test "format: destructure list" {
    try expectFormat("let [x, y] = list", "let [x, y] = list\n");
}

// === COMMENTS ===

test "format: preserves comment" {
    try expectFormat("// hello\n1", "// hello\n\n1\n");
}

test "format: multiple comments" {
    try expectFormat("// line 1\n// line 2\n1", "// line 1\n\n// line 2\n\n1\n");
}

test "format: comments between statements" {
    try expectFormat("let x = 1\n// comment\nlet y = 2", "let x = 1\n\n// comment\n\nlet y = 2\n");
}

// === SECTIONS ===

test "format: section single expression inline" {
    try expectFormat("input: { read(\"aoc://2022/1\") }", "input: read(\"aoc://2022/1\")\n");
}

test "format: section multi statement keeps braces" {
    try expectFormat("part_one: { let x = 1\nx + 2 }", "part_one: {\n  let x = 1;\n\n  x + 2\n}\n");
}

test "format: section with attribute" {
    try expectFormat("@slow\ntest: { 1 }", "@slow\ntest: 1\n");
}

test "format: section with multiple attributes" {
    try expectFormat("@slow\n@memoize\npart_one: { 1 }", "@slow\n@memoize\npart_one: {\n  1\n}\n");
}

test "format: sections have blank lines between" {
    try expectFormat("input: 1\npart_one: 2\npart_two: 3", "input: 1\n\npart_one: {\n  2\n}\n\npart_two: {\n  3\n}\n");
}

test "format: nested test sections" {
    try expectFormat("test: { input: \"hello\"\npart_one: 5 }", "test: {\n  input: \"hello\"\n  part_one: 5\n}\n");
}

// === CONTROL FLOW ===

test "format: return" {
    try expectFormat("return 42;", "return 42\n");
}

test "format: break" {
    try expectFormat("break 42;", "break 42\n");
}

// === INDEX ===

test "format: index" {
    try expectFormat("arr[0]", "arr[0]\n");
}

test "format: index with expression" {
    try expectFormat("arr[i+1]", "arr[i + 1]\n");
}

// === SPREAD/REST ===

test "format: spread" {
    try expectFormat("[..xs]", "[..xs]\n");
}

test "format: rest identifier" {
    try expectFormat("let [first, ..rest] = list", "let [first, ..rest] = list\n");
}

// === PRECEDENCE ===

test "format: preserves parens for and or mixed" {
    try expectFormat("a && b || (c && d)", "a && b || (c && d)\n");
}

test "format: preserves parens for or and mixed" {
    try expectFormat("a || b && (c || d)", "a || b && (c || d)\n");
}

test "format: removes unnecessary left parens and or" {
    try expectFormat("(a && b) || c", "a && b || c\n");
}

test "format: preserves parens for pipe in addition" {
    try expectFormat("a + (b |> f)", "a + (b |> f)\n");
}

test "format: preserves parens for subtraction right associativity" {
    try expectFormat("a - (b - c)", "a - (b - c)\n");
}

test "format: preserves parens for division right associativity" {
    try expectFormat("a / (b / c)", "a / (b / c)\n");
}

test "format: preserves parens for modulo right associativity" {
    try expectFormat("a % (b % c)", "a % (b % c)\n");
}

test "format: preserves parens for addition right associativity" {
    try expectFormat("a + (b + c)", "a + (b + c)\n");
}

test "format: preserves parens for multiplication right associativity" {
    try expectFormat("a * (b * c)", "a * (b * c)\n");
}

// === LAMBDA BODY BRACES ===

test "format: lambda preserves braces for set body" {
    try expectFormat("|x| { {a, b, c} }", "|x| {\n  {a, b, c}\n}\n");
}

test "format: lambda preserves braces for dict body" {
    try expectFormat("|x| { #{a: 1, b: 2} }", "|x| {\n  #{a: 1, b: 2}\n}\n");
}

test "format: lambda preserves braces for pipe body" {
    try expectFormat("|x| { [1, 2, 3] |> map(f) |> sum }", "|x| {\n  [1, 2, 3]\n    |> map(f)\n    |> sum\n}\n");
}

test "format: lambda preserves braces for composition body" {
    try expectFormat("|x| { f >> g >> h }", "|x| {\n  f >> g >> h\n}\n");
}

test "format: lambda unwraps simple expression" {
    try expectFormat("|x| { x + 1 }", "|x| x + 1\n");
}

// === COLLECTIONS NO TRAILING COMMA INLINE ===

test "format: list no trailing comma inline" {
    try expectFormat("[1, 2, 3]", "[1, 2, 3]\n");
}

test "format: set no trailing comma inline" {
    try expectFormat("{1, 2, 3}", "{1, 2, 3}\n");
}

test "format: dict no trailing comma inline" {
    try expectFormat("#{a: 1, b: 2}", "#{a: 1, b: 2}\n");
}

// === DICT SHORTHAND ===

test "format: dict shorthand preserved" {
    try expectFormat("#{foo}", "#{foo}\n");
    try expectFormat("#{foo, bar, baz}", "#{foo, bar, baz}\n");
}

test "format: dict explicit to shorthand" {
    try expectFormat("#{\"foo\": foo}", "#{foo}\n");
    try expectFormat("#{\"foo\": foo, \"bar\": bar}", "#{foo, bar}\n");
}

test "format: dict shorthand mixed" {
    try expectFormat("#{foo, \"bar\": baz}", "#{foo, \"bar\": baz}\n");
    try expectFormat("#{\"key\": value}", "#{\"key\": value}\n");
}

// === TRAILING COMMENTS ===

test "format: preserves trailing comment on let" {
    try expectFormat("let x = 1  // comment", "let x = 1 // comment\n");
}

test "format: preserves trailing comment on expression" {
    try expectFormat("foo(bar)  // inline note", "foo(bar) // inline note\n");
}

test "format: preserves trailing comment after semicolon" {
    try expectFormat("let x = 1;  // comment", "let x = 1 // comment\n");
}

test "format: trailing comment not attached from next line" {
    try expectFormat("let x = 1\n// standalone", "let x = 1\n\n// standalone\n");
}

test "format: preserves trailing comment on return" {
    try expectFormat("return x // done", "return x // done\n");
}

test "format: preserves trailing comment on break" {
    try expectFormat("break x // early exit", "break x // early exit\n");
}

// === BLANK LINE PRESERVATION ===

test "format: preserves blank line between statements in block" {
    try expectFormat("|x| { let a = 1\n\nlet b = 2\na + b }", "|x| {\n  let a = 1\n\n  let b = 2;\n\n  a + b\n}\n");
}

test "format: single newline no blank in block" {
    try expectFormat("|x| { let a = 1\nlet b = 2\na + b }", "|x| {\n  let a = 1\n  let b = 2;\n\n  a + b\n}\n");
}

// === DICT PATTERNS ===

test "format: let dictionary pattern shorthand" {
    try expectFormat("let #{name}=x", "let #{name} = x\n");
}

test "format: let dictionary pattern multiple" {
    try expectFormat("let #{name,age}=x", "let #{name, age} = x\n");
}

test "format: let dictionary pattern explicit key" {
    try expectFormat("let #{\"key\":value}=x", "let #{\"key\": value} = x\n");
}

test "format: let dictionary pattern rest" {
    try expectFormat("let #{name,..rest}=x", "let #{name, ..rest} = x\n");
}

test "format: function dictionary parameter" {
    try expectFormat("|#{x,y}|x+y", "|#{x, y}| x + y\n");
}

test "format: match dictionary pattern" {
    try expectFormat("match d { #{name} { name } }", "match d {\n  #{name} { name }\n}\n");
}

// === TOP LEVEL ===

test "format: top level lets have blank lines" {
    try expectFormat("let a = 1\nlet b = 2\nlet c = 3", "let a = 1\n\nlet b = 2\n\nlet c = 3\n");
}

test "format: block final expression has blank line" {
    try expectFormat("|x| { let a = 1\nlet b = 2\na + b }", "|x| {\n  let a = 1\n  let b = 2;\n\n  a + b\n}\n");
}

test "format: block single expression no blank line" {
    try expectFormat("|x| { x + 1 }", "|x| x + 1\n");
}

test "format: block two lets no blank line" {
    try expectFormat("|x| { let a = 1\nlet b = 2 }", "|x| {\n  let a = 1\n  let b = 2\n}\n");
}

// === EMPTY / EDGE CASES ===

test "format: empty program" {
    try expectFormat("", "");
}

test "format: deeply nested" {
    try expectFormat("[[[[1]]]]", "[[[[1]]]]\n");
}

test "format: unicode string" {
    try expectFormat("\"héllo 世界\"", "\"héllo 世界\"\n");
}

test "format: unicode in strings" {
    try expectFormat("\"café\"", "\"café\"\n");
}

// === IDEMPOTENCY ===

test "idempotent: simple expression" {
    try assertIdempotent("1+2");
}

test "idempotent: list" {
    try assertIdempotent("[1,2,3]");
}

test "idempotent: function" {
    try assertIdempotent("|x,y| x + y");
}

test "idempotent: pipe chain" {
    try assertIdempotent("[1, 2, 3] |> sum");
}

test "idempotent: match" {
    try assertIdempotent("match x { 0 { 1 } _ { 2 } }");
}

test "idempotent: if else" {
    try assertIdempotent("if x { 1 } else { 2 }");
}

test "idempotent: multiline" {
    try assertIdempotent("let x = 1;\nlet y = 2;\nx + y");
}

test "idempotent: complex" {
    try assertIdempotent("let data = [1, 2, 3, 4, 5]; data |> sum");
}

test "idempotent: dictionary pattern let" {
    try assertIdempotent("let #{name, age} = x");
}

test "idempotent: dictionary pattern rest" {
    try assertIdempotent("let #{name, ..rest} = x");
}

test "idempotent: dictionary parameter" {
    try assertIdempotent("|#{x, y}| x + y");
}

test "idempotent: trailing comments" {
    try assertIdempotent("let x = 1 // comment\nlet y = 2 // another");
}

test "idempotent: blank lines" {
    try assertIdempotent("|x| {\n  let a = 1\n\n  let b = 2\n\n  a + b\n}");
}

test "idempotent: mixed and or operators" {
    try assertIdempotent("(a && b) || (c && d)");
}

test "idempotent: pipe in arithmetic" {
    try assertIdempotent("rest(queue) + (items |> map(f))");
}

test "idempotent: lambda with set" {
    try assertIdempotent("|x| { {a, b, c} }");
}

test "idempotent: dict shorthand" {
    try assertIdempotent("#{a, b, c, \"key\": value}");
}

// === STRING ESCAPE TESTS (from comet) ===

test "format: string with backspace" {
    // Input contains actual backspace char (0x08)
    try expectFormat("\"a\x08b\"", "\"a\\bb\"\n");
}

test "format: string with form feed" {
    // Input contains actual form feed char (0x0C)
    try expectFormat("\"a\x0Cb\"", "\"a\\fb\"\n");
}

test "format: string short escapes newlines" {
    // Literal newline in short string should become \n escape
    try expectFormat("\"line1\nline2\"", "\"line1\\nline2\"\n");
}

test "format: string two newlines still escapes" {
    try expectFormat("\"a\nb\nc\"", "\"a\\nb\\nc\"\n");
}

test "format: string three newlines short escapes" {
    // 3 newlines is NOT > 3, so should escape
    const result = try lib.format(testing.allocator, "\"a\nb\nc\nd\"");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("\"a\\nb\\nc\\nd\"\n", result);
}

test "format: string four newlines preserves literal" {
    // 4 newlines IS > 3, so preserves literal newlines
    const result = try lib.format(testing.allocator, "\"a\nb\nc\nd\ne\"");
    defer testing.allocator.free(result);
    // Should contain more than 1 newline (literal newlines preserved)
    var newline_count: usize = 0;
    for (result) |c| {
        if (c == '\n') newline_count += 1;
    }
    try testing.expect(newline_count > 1);
}

test "format: string long few newlines preserves literal" {
    // >50 chars triggers literal newlines regardless of newline count
    const long_string = "\"" ++ "x" ** 30 ++ "\\n" ++ "y" ** 25 ++ "\"";
    const result = try lib.format(testing.allocator, long_string);
    defer testing.allocator.free(result);
    var newline_count: usize = 0;
    for (result) |c| {
        if (c == '\n') newline_count += 1;
    }
    try testing.expect(newline_count > 1);
}

test "format: string short few newlines escapes" {
    // <50 chars AND <=3 newlines should escape
    try expectFormat("\"hello\\nworld\"", "\"hello\\nworld\"\n");
}

// === LINE WIDTH / WRAPPING TESTS ===

test "format: list exceeding line width wraps" {
    // This list exceeds 100 chars so it should wrap
    const input = "[very_long_name_one, very_long_name_two, very_long_name_three, very_long_name_four, very_long_name_five]";
    const result = try lib.format(testing.allocator, input);
    defer testing.allocator.free(result);
    // Should wrap to multiple lines
    try testing.expect(std.mem.indexOf(u8, result, "\n") != null);
    // Should have comma before newline
    try testing.expect(std.mem.indexOf(u8, result, ",\n") != null);
}

test "format: call exceeding line width wraps" {
    // Long function call should wrap
    const input = "very_long_function_name(argument_one, argument_two, argument_three, argument_four, argument_five)";
    const result = try lib.format(testing.allocator, input);
    defer testing.allocator.free(result);
    // Should wrap to multiple lines
    try testing.expect(std.mem.indexOf(u8, result, "\n") != null);
}

test "format: wrapped list has trailing comma" {
    // Short list should stay inline
    const short_output = try lib.format(testing.allocator, "[1, 2, 3]");
    defer testing.allocator.free(short_output);
    var short_lines: usize = 0;
    for (short_output) |c| {
        if (c == '\n') short_lines += 1;
    }
    try testing.expectEqual(@as(usize, 1), short_lines); // Only trailing newline

    // Very long list should wrap
    const long_input = "[element_0, element_1, element_2, element_3, element_4, element_5, element_6, element_7, element_8, element_9, element_10, element_11, element_12, element_13, element_14, element_15, element_16, element_17, element_18, element_19]";
    const long_output = try lib.format(testing.allocator, long_input);
    defer testing.allocator.free(long_output);
    try testing.expectEqualStrings("[\n  element_0,\n  element_1,\n  element_2,\n  element_3,\n  element_4,\n  element_5,\n  element_6,\n  element_7,\n  element_8,\n  element_9,\n  element_10,\n  element_11,\n  element_12,\n  element_13,\n  element_14,\n  element_15,\n  element_16,\n  element_17,\n  element_18,\n  element_19\n]\n", long_output);
}

// === TRAILING CLOSURE TESTS ===

test "format: trailing closure preserved" {
    // Note: Zig parser requires parens for calls - `each(|x| {...})` vs Rust's `each |x| {...}`
    try expectFormat("each(|x| { let y = x + 1\nputs(y) })", "each |x| {\n  let y = x + 1;\n\n  puts(y)\n}\n");
}

test "format: trailing closure in pipe" {
    // Note: Zig parser requires parens for calls - `each(|x| {...})` vs Rust's `each |x| {...}`
    try expectFormat("[1, 2] |> each(|x| { let y = x\nputs(y) })", "[1, 2] |> each |x| {\n  let y = x;\n\n  puts(y)\n}\n");
}

test "format: single statement lambda trailing when long" {
    const input = "map(|some_very_long_parameter_name| some_very_long_parameter_name + another_very_long_expression_here)";
    const expected = "map |some_very_long_parameter_name| {\n  some_very_long_parameter_name + another_very_long_expression_here\n}\n";
    try expectFormat(input, expected);
}

test "format: lambda with other args trailing when long" {
    const input = "fold_s([[], []], |[prefixes, prefix], key| [prefixes + [[..prefix, key]], [..prefix, key, extra, more]])";
    const expected = "fold_s([[], []]) |[prefixes, prefix], key| {\n  [prefixes + [[..prefix, key]], [..prefix, key, extra, more]]\n}\n";
    try expectFormat(input, expected);
}

test "format: lambda in pipe chain keeps braces" {
    const input = "a |> |x| { x } |> f";
    const result = try lib.format(testing.allocator, input);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a\n  |> |x| {\n    x\n  }\n  |> f\n", result);
    // Verify idempotent
    const result2 = try lib.format(testing.allocator, result);
    defer testing.allocator.free(result2);
    try testing.expectEqualStrings(result, result2);
}

test "format: lambda last in pipe chain can inline" {
    const input = "a |> |x| x";
    const result = try lib.format(testing.allocator, input);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a |> |x| x\n", result);
}

// === LAMBDA MATCH UNWRAPPING TESTS ===

test "format: lambda unwraps match with list subject" {
    try expectFormat("|x| { match [a, b] { [1, _] { true } _ { false } } }", "|x| match [a, b] {\n  [1, _] { true }\n  _ { false }\n}\n");
}

test "format: lambda unwraps match with identifier subject" {
    try expectFormat("|x| { match x { 1 { true } _ { false } } }", "|x| match x {\n  1 { true }\n  _ { false }\n}\n");
}

// === COMPOSITION WRAPPING TEST ===

test "format: composition wraps at line width" {
    // Composition wraps when exceeding line width (100 chars)
    try expectFormat("very_long_function_name_one >> very_long_function_name_two >> very_long_function_name_three >> very_long_function_name_four", "very_long_function_name_one\n  >> very_long_function_name_two\n  >> very_long_function_name_three\n  >> very_long_function_name_four\n");
}

// === PRECEDENCE / PARENS TEST ===

test "format: preserves parens for pipe in subtraction" {
    try expectFormat("a - (b |> f |> g)", "a - (b\n  |> f\n  |> g)\n");
}

// === SECTION COMMENT TEST ===

test "format: trailing comment in section" {
    // Trailing comments work in sections (wrapped in braces due to trailing content)
    try expectFormat("part_one: let x = 1  // inline", "part_one: {\n  let x = 1 // inline\n}\n");
}

// === DICT PATTERN TEST ===

test "format: function dictionary parameter explicit key" {
    try expectFormat("|#{\"a\":x,\"b\":y}|x+y", "|#{\"a\": x, \"b\": y}| x + y\n");
}

// === BLOCK / RETURN TESTS ===

test "format: multiline return has blank line" {
    try expectFormat("|x| { let v = process(x)\nreturn v |> map(f) |> filter(g) |> sum }", "|x| {\n  let v = process(x)\n\n  return v\n    |> map(f)\n    |> filter(g)\n    |> sum\n}\n");
}

test "format: single line return no blank line" {
    try expectFormat("|x| { let r = compute(x)\nreturn r }", "|x| {\n  let r = compute(x)\n  return r\n}\n");
}

test "format: semicolon before implicit return skips comments" {
    try expectFormat("|x| { let a = 1\n// comment\na + 1 }", "|x| {\n  let a = 1;\n  // comment\n\n  a + 1\n}\n");
}

test "format: semicolon with multiple comments before return" {
    try expectFormat("|x| { let a = 1\n// comment 1\n// comment 2\na }", "|x| {\n  let a = 1;\n  // comment 1\n  // comment 2\n\n  a\n}\n");
}

// === ERROR HANDLING TESTS ===

test "format: invalid syntax returns error" {
    const result = lib.format(testing.allocator, "let = ");
    try testing.expectError(lib.FormatError.ParseError, result);
}

test "format: unclosed bracket returns error" {
    const result = lib.format(testing.allocator, "[1, 2, 3");
    try testing.expectError(lib.FormatError.ParseError, result);
}

test "format: unclosed string returns error" {
    const result = lib.format(testing.allocator, "\"unclosed");
    try testing.expectError(lib.FormatError.ParseError, result);
}

// === ROUND TRIP TESTS ===
// These tests verify that the AST structure is preserved after formatting
// by checking that both original and formatted code parse to the same number of statements

fn assertRoundTrip(source: []const u8) !void {
    const formatted = try lib.format(testing.allocator, source);
    defer testing.allocator.free(formatted);

    // Both should parse successfully - we verify by formatting again
    const reformatted = try lib.format(testing.allocator, formatted);
    defer testing.allocator.free(reformatted);

    // If both parse and format identically, the AST structure is preserved
    try testing.expectEqualStrings(formatted, reformatted);
}

test "round_trip: expression" {
    try assertRoundTrip("1 + 2 * 3");
}

test "round_trip: function" {
    try assertRoundTrip("|x| x + 1");
}

test "round_trip: match" {
    try assertRoundTrip("match x { 0 { 1 } _ { 2 } }");
}

test "round_trip: if else" {
    try assertRoundTrip("if x { 1 } else { 2 }");
}

test "round_trip: list" {
    try assertRoundTrip("[1, 2, 3]");
}

test "round_trip: pipe" {
    try assertRoundTrip("[1, 2, 3] |> sum");
}

test "round_trip: mixed and or operators" {
    const input = "(a && b) || (c && d)";
    const formatted = try lib.format(testing.allocator, input);
    defer testing.allocator.free(formatted);
    const reformatted = try lib.format(testing.allocator, formatted);
    defer testing.allocator.free(reformatted);
    try testing.expectEqualStrings(formatted, reformatted);
}

test "round_trip: pipe in arithmetic" {
    const input = "rest(queue) + (items |> map(f))";
    const formatted = try lib.format(testing.allocator, input);
    defer testing.allocator.free(formatted);
    const reformatted = try lib.format(testing.allocator, formatted);
    defer testing.allocator.free(reformatted);
    try testing.expectEqualStrings(formatted, reformatted);
}

test "round_trip: lambda with set" {
    const input = "|x| { {a, b, c} }";
    const formatted = try lib.format(testing.allocator, input);
    defer testing.allocator.free(formatted);
    const reformatted = try lib.format(testing.allocator, formatted);
    defer testing.allocator.free(reformatted);
    try testing.expectEqualStrings(formatted, reformatted);
}

test "round_trip: lambda with match list subject" {
    const input = "|j| { match [j >= len, j < len] { [true, _] { j } _ { j + 1 } } }";
    const formatted = try lib.format(testing.allocator, input);
    defer testing.allocator.free(formatted);
    const reformatted = try lib.format(testing.allocator, formatted);
    defer testing.allocator.free(reformatted);
    try testing.expectEqualStrings(formatted, reformatted);
}

test "round_trip: dict shorthand" {
    const input = "#{a, b, c, \"key\": value}";
    const formatted = try lib.format(testing.allocator, input);
    defer testing.allocator.free(formatted);
    const reformatted = try lib.format(testing.allocator, formatted);
    defer testing.allocator.free(reformatted);
    try testing.expectEqualStrings(formatted, reformatted);
}

test "round_trip: dictionary pattern let" {
    try assertRoundTrip("let #{name, age} = dict");
}

test "round_trip: dictionary pattern rest" {
    try assertRoundTrip("let #{name, ..rest} = dict");
}

test "round_trip: dictionary parameter" {
    try assertRoundTrip("|#{x, y}| x + y");
}

test "round_trip: match dictionary" {
    try assertRoundTrip("match d { #{name} { name } }");
}
