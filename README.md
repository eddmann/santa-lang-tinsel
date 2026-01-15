<p align="center"><a href="https://eddmann.com/santa-lang/"><img src="./docs/logo.png" alt="santa-lang" width="400px" /></a></p>

# santa-lang Tinsel

Opinionated code formatter for [santa-lang](https://eddmann.com/santa-lang/), written in Zig.

## Overview

santa-tinsel is a fast, opinionated code formatter that enforces a single canonical style for santa-lang code. It uses the Wadler-Lindig pretty printing algorithm for intelligent line-breaking decisions.

Key features:

- **Fast** - Written in Zig for optimal performance
- **Opinionated** - One canonical style, no configuration needed
- **Idempotent** - Running the formatter twice produces the same output
- **Intelligent line-breaking** - Uses the Wadler-Lindig pretty printing algorithm
- **Comment-preserving** - Keeps standalone and trailing comments intact
- **Zero dependencies** - Pure Zig with no external dependencies

## Architecture

```
Source Code → Lexer → Parser → Builder → Printer → Formatted Code
                         ↓          ↓
                        AST      Doc IR
```

| Component   | Description                                              |
| ----------- | -------------------------------------------------------- |
| **Lexer**   | Tokenizes source into keywords, operators, literals      |
| **Parser**  | Builds an Abstract Syntax Tree (AST) using Pratt parsing |
| **Builder** | Converts AST to Wadler-Lindig document IR                |
| **Printer** | Renders document IR with intelligent line-breaking       |

## Installation

### Release Binaries

Download pre-built binaries from [GitHub Releases](https://github.com/eddmann/santa-lang-tinsel/releases):

| Platform              | Artifact                             |
| --------------------- | ------------------------------------ |
| Linux (x86_64)        | `santa-tinsel-{version}-linux-amd64` |
| Linux (ARM64)         | `santa-tinsel-{version}-linux-arm64` |
| macOS (Intel)         | `santa-tinsel-{version}-macos-amd64` |
| macOS (Apple Silicon) | `santa-tinsel-{version}-macos-arm64` |
| WebAssembly (WASI)    | `santa-tinsel-{version}.wasm`        |

## Usage

```bash
# Format stdin to stdout
echo 'let x=1+2' | santa-tinsel

# Format a file to stdout
santa-tinsel solution.santa

# Format a file in place
santa-tinsel -w solution.santa

# List files that differ from formatted (useful for CI)
santa-tinsel -l solution.santa

# Show diff of changes
santa-tinsel -d solution.santa

# Format all .santa files in a directory recursively
santa-tinsel -w src/
```

### Options

| Flag | Description                                         |
| ---- | --------------------------------------------------- |
| -w   | Write result to source file (format in place)       |
| -l   | List files whose formatting differs (exit 1 if any) |
| -d   | Display diffs instead of rewriting files            |
| -h   | Display help and exit                               |

## Example

The formatter enforces consistent style:

```
# Input                          # Output
1+2                              1 + 2
[1,2,3]                          [1, 2, 3]
|x|x+1                           |x| x + 1
let x=1                          let x = 1
#{"foo":foo}                     #{foo}
```

### Pipe Chains

Two-element pipes stay inline, three or more expand vertically:

```santa
# Inline (2 elements)
[1, 2] |> sum

# Expanded (3+ elements)
input
  |> lines
  |> filter(is_valid?)
  |> size
```

### Lambdas

Single-expression lambdas stay inline, multi-statement expand:

```santa
# Inline
|x| x + 1

# Expanded
|x| {
  let y = x + 1;

  y
}
```

## Building

Requires Zig 0.15.x:

```bash
# Build CLI (debug)
make build

# Build CLI (release)
make release

# Run tests
make test

# Run all CI checks (lint + test)
make can-release
```

The executable will be at `zig-out/bin/santa-tinsel`.

## Development

Run `make help` to see all available targets:

```bash
make help          # Show all targets
make fmt           # Format Zig source code
make lint          # Run zig fmt --check
make test          # Run all tests
make can-release   # Run before submitting PR (lint + test)
```

## Project Structure

```
├── src/
│   ├── token.zig          # Token definitions
│   ├── lexer.zig          # Tokenization
│   ├── ast.zig            # AST node definitions
│   ├── parser.zig         # Pratt parser
│   ├── doc.zig            # Wadler-Lindig document IR
│   ├── builder.zig        # AST to document IR
│   ├── printer.zig        # Document IR to string
│   ├── lib.zig            # Public API
│   ├── main.zig           # CLI entry point
│   └── formatter_test.zig # Test suite
└── .github/workflows/     # CI/CD configuration
```

## Formatting Rules

| Rule                   | Example                                |
| ---------------------- | -------------------------------------- |
| Operators with spaces  | `1 + 2`, `x == y`                      |
| Prefix operators tight | `!true`, `-42`                         |
| Collections with comma | `[1, 2, 3]`, `{a, b}`                  |
| Bindings with spaces   | `let x = 1`                            |
| 100-char line width    | Lines break intelligently at 100 chars |
| 2-space indentation    | Consistent indent level                |
| Dict shorthand         | `#{"foo": foo}` → `#{foo}`             |

## Reindeer (implementations)

The language has been implemented multiple times to explore different execution models and technologies.

| Codename                                                 | Type                     | Language   |
| -------------------------------------------------------- | ------------------------ | ---------- |
| [Comet](https://github.com/eddmann/santa-lang-comet)     | Tree-walking interpreter | Rust       |
| [Blitzen](https://github.com/eddmann/santa-lang-blitzen) | Bytecode VM              | Rust       |
| [Dasher](https://github.com/eddmann/santa-lang-dasher)   | LLVM native compiler     | Rust       |
| [Donner](https://github.com/eddmann/santa-lang-donner)   | JVM bytecode compiler    | Kotlin     |
| [Vixen](https://github.com/eddmann/santa-lang-vixen)     | Embedded bytecode VM     | C          |
| [Prancer](https://github.com/eddmann/santa-lang-prancer) | Tree-walking interpreter | TypeScript |

## Tooling

| Name                                                         | Description |
| ------------------------------------------------------------ | ----------- |
| [Workbench](https://github.com/eddmann/santa-lang-workbench) | Desktop IDE |

## License

MIT License - see [LICENSE](LICENSE) for details.
