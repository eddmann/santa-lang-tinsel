# santa-lang Implementation

This is **Format**, a santa-lang tool implementation. santa-lang is a functional programming language designed for solving Advent of Code puzzles. Multiple implementations exist to explore different execution models.

## Project Overview

- **Format**: Opinionated code formatter written in Zig
- Architecture: Source → Lexer → Parser → AST → Builder → Doc IR → Printer
- Wadler-Lindig pretty printing algorithm for intelligent line-breaking
- No external dependencies (Zig standard library only)

## Makefile

**Always use Makefile targets.** Never run build tools directly.

- Run `make help` to see all available targets
- `make fmt` for code formatting
- `make test` for running tests
- `make can-release` before submitting a PR (runs lint + all tests)

This ensures consistent, reproducible builds across all environments.

## Setup

```bash
# Requires Zig 0.15.x
make build              # Debug build
make release            # Release build (optimized)
```

## Common Commands

```bash
make help               # Show available targets
make fmt                # Format Zig source code
make lint               # Run zig fmt --check
make test               # Run all tests (340 tests)
make can-release        # Run before submitting PR (lint + test)
make release            # Build optimized release binary
make run ARGS="file.santa"  # Run formatter on file
```

## Code Conventions

- **Language**: Zig 0.15.x
- **Formatting**: `zig fmt` defaults
- **Linting**: `zig fmt --check` (must pass)
- **Testing**: Inline tests + dedicated `formatter_test.zig`
- **Architecture**: `lexer` → `parser` → `ast` → `builder` → `doc` → `printer`
- **Dependencies**: None (Zig std only)

## Source Files

| File | Purpose |
|------|---------|
| `token.zig` | Token definitions and source locations |
| `lexer.zig` | Tokenization with lookahead buffering |
| `parser.zig` | Pratt parser for AST construction |
| `ast.zig` | AST node definitions (25+ expression types) |
| `doc.zig` | Wadler-Lindig document IR primitives |
| `builder.zig` | AST to document IR conversion |
| `printer.zig` | Document IR to formatted string with line-breaking |
| `lib.zig` | Public library API (`format`, `isFormatted`) |
| `main.zig` | CLI entry point with file/directory handling |
| `formatter_test.zig` | Comprehensive test suite (260+ tests) |

## Tests & CI

- **CI** (`test.yml`): Runs `make can-release` on ubuntu-24.04
- **Build** (`build-cli.yml`): Multi-platform builds (linux/macos, amd64/arm64)
- Auto-updates `draft-release` branch after tests pass on main
- 340 tests covering lexer, parser, doc, printer, and formatting

## PR & Workflow Rules

- **Branches**: `main` for development, `draft-release` auto-updated from CI
- **Commit format**: Conventional commits (feat:, fix:, refactor:, etc.)
- **CI gates**: All tests must pass before merge
- **Release**: Push to draft-release triggers build workflow

## Security & Gotchas

- **File size limit**: 10MB max file size for formatting (in main.zig)
- **Memory**: Uses arena allocators for Doc IR; freed in bulk after formatting
- **Line width**: Hardcoded to 100 characters (printer.zig LINE_WIDTH)
- **Indent size**: Hardcoded to 2 spaces (builder.zig INDENT_SIZE)
- **No config file**: Formatter is fully opinionated, no customization
- **Idempotency**: Formatting is guaranteed idempotent (tested)
