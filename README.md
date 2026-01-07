# santa-fmt

An opinionated code formatter for [santa-lang](https://github.com/eddmann/santa-lang), written in Zig.

## Features

- **Fast** - Written in Zig for optimal performance
- **Opinionated** - One canonical style, no configuration needed
- **Idempotent** - Running the formatter twice produces the same output
- **Intelligent line-breaking** - Uses the Wadler-Lindig pretty printing algorithm
- **Comment-preserving** - Keeps standalone and trailing comments intact
- **Library & CLI** - Use as a library or command-line tool

## Building

Requires Zig 0.15.x:

```bash
# Build the CLI
zig build

# Run tests
zig build test

# Build optimized release
zig build -Doptimize=ReleaseFast
```

The executable will be at `zig-out/bin/santa-fmt`.

## Usage

### Command Line

```bash
# Format stdin to stdout
echo 'let x=1+2' | santa-fmt
# Output: let x = 1 + 2

# Format a file to stdout
santa-fmt program.santa

# Format a file in place
santa-fmt --fmt-write program.santa

# Check if a file is formatted (exit 1 if not)
santa-fmt --fmt-check program.santa

# Format an expression directly
santa-fmt -e '[1,2,3]|>sum'
# Output: [1, 2, 3] |> sum
```

### Options

| Flag | Description |
|------|-------------|
| `-f, --fmt` | Format to stdout (default) |
| `-w, --fmt-write` | Format file in place |
| `-c, --fmt-check` | Check if formatted (exit 1 if not) |
| `-e <expr>` | Format expression from argument |
| `-h, --help` | Show help message |

### Library

```zig
const std = @import("std");
const santa_fmt = @import("lib.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Format source code
    const formatted = try santa_fmt.format(allocator, "let x=1+2");
    defer allocator.free(formatted);
    // formatted == "let x = 1 + 2\n"

    // Check if already formatted
    const is_formatted = try santa_fmt.isFormatted(allocator, "let x = 1 + 2\n");
    // is_formatted == true
}
```

## Formatting Rules

### Spacing

Operators are surrounded by spaces:
```
1+2        →  1 + 2
x==y       →  x == y
a&&b||c    →  a && b || c
```

Prefix operators have no space after:
```
! true     →  !true
- 42       →  -42
```

### Collections

Collections use comma-space separation:
```
[1,2,3]           →  [1, 2, 3]
{a,b,c}           →  {a, b, c}
#{a:1,b:2}        →  #{a: 1, b: 2}
```

### Bindings

Bindings have spaces around `=`:
```
let x=1           →  let x = 1
let mut y=2       →  let mut y = 2
x=3               →  x = 3
```

### Lambdas

Single-expression lambdas stay inline:
```
|x|x+1            →  |x| x + 1
|x,y|x+y          →  |x, y| x + y
```

Multi-statement lambdas expand:
```
|x| { let y = x + 1; y }
```
becomes:
```
|x| {
  let y = x + 1;

  y
}
```

### Pipe Chains

Two-element pipes stay inline:
```
[1, 2] |> sum
```

Three or more elements expand vertically:
```
input
  |> lines
  |> filter(is_nice?)
  |> size
```

### Function Composition

Composition chains stay inline when they fit:
```
f >> g >> h
```

### If-Else

Simple if-else stays inline:
```
if x { 1 } else { 2 }
```

Complex bodies expand:
```
if x {
  let y = 1;

  y
} else {
  2
}
```

### Match

Match cases are indented:
```
match x {
  0 { "zero" }
  n if n > 0 { "positive" }
  _ { "negative" }
}
```

### Sections

Single-expression sections collapse:
```
input: { read("aoc://2022/1") }  →  input: read("aoc://2022/1")
```

Multi-statement sections expand:
```
part_one: {
  let x = 1;

  x + 2
}
```

### Comments

Standalone comments are preserved with blank lines:
```
// comment

let x = 1
```

Trailing comments are preserved:
```
let x = 1 // inline note
```

### Ranges

Ranges have no spaces:
```
1..10
1..=10
1..
```

### Dictionary Shorthand

Dictionary shorthand is used when key matches value:
```
#{\"foo\": foo}  →  #{foo}
```

### Line Width

The formatter targets 100-character line width, breaking lines intelligently when content exceeds this limit.

### Indentation

Uses 2 spaces for indentation.

## Architecture

The formatter uses a three-phase architecture:

```
Source Code → Parse → AST → Build → Doc IR → Print → Formatted Code
```

### Components

| File | Description |
|------|-------------|
| `token.zig` | Token definitions and source locations |
| `lexer.zig` | Tokenizer - converts source to tokens |
| `ast.zig` | Abstract syntax tree node definitions |
| `parser.zig` | Pratt parser - builds AST from tokens |
| `doc.zig` | Document IR primitives (Wadler-Lindig) |
| `builder.zig` | Converts AST to document IR |
| `printer.zig` | Renders document IR to formatted string |
| `lib.zig` | Public API |
| `main.zig` | CLI entry point |

### Document IR

The formatter uses the Wadler-Lindig pretty printing algorithm with these document primitives:

- `nil` - Empty document
- `text` - Literal text
- `line` - Soft line break (space in flat mode, newline in break mode)
- `hard_line` - Always a newline with indentation
- `blank_line` - Always a newline without indentation
- `concat` - Sequence of documents
- `group` - Try to fit on one line, break if too long
- `nest` - Increase indentation for nested content
- `if_break` - Different content for flat vs break mode

## Testing

The test suite includes:

- **Lexer tests** - Token recognition for all syntax
- **Parser tests** - AST construction for all expressions
- **Formatter tests** - Input/output formatting expectations
- **Idempotency tests** - Verify formatting is stable

Run all tests:
```bash
zig build test --summary all
```

## Supported Syntax

### Literals
- Integers: `42`, `1_000_000`
- Decimals: `3.14`, `1_000.50`
- Strings: `"hello"`, `"escaped\n\t\""`
- Booleans: `true`, `false`
- Nil: `nil`
- Placeholder: `_`

### Operators
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`
- Logical: `&&`, `||`, `!`
- Backtick: `` `func` ``

### Collections
- Lists: `[1, 2, 3]`
- Sets: `{1, 2, 3}`
- Dictionaries: `#{a: 1, b: 2}`, `#{foo}` (shorthand)

### Ranges
- Exclusive: `1..10`
- Inclusive: `1..=10`
- Unbounded: `1..`

### Functions
- Lambdas: `|x| x + 1`, `|x, y| x + y`, `|| 42`
- Calls: `f()`, `f(1, 2, 3)`
- Pipe chains: `x |> f |> g`
- Composition: `f >> g >> h`

### Bindings
- Let: `let x = 1`
- Mutable let: `let mut x = 1`
- Assignment: `x = 2`
- Destructuring: `let [a, b] = list`, `let #{name} = dict`

### Control Flow
- If-else: `if x { 1 } else { 2 }`
- Match: `match x { 0 { "zero" } _ { "other" } }`
- Return: `return x`
- Break: `break x`

### Sections
- Named: `part_one: { ... }`
- With attributes: `@slow\ntest: { ... }`

### Patterns
- List patterns: `[first, ..rest]`
- Dict patterns: `#{name, age}`, `#{\"key\": value}`
- Spread: `[..xs]`

## License

MIT
