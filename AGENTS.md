## santa-lang Formatter

This is **santa-fmt**, a code formatter for santa-lang written in Zig.

## Project Overview

- Opinionated formatter implementing Wadler-Lindig pretty printing
- Single executable CLI tool
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
make build              # Build the project
make test               # Run tests
```

## Common Commands

```bash
make help               # Show available targets
make fmt                # Format Zig code
make lint               # Run zig fmt --check
make test               # Run all tests
make can-release        # Run before submitting PR (lint + test)
make release            # Build optimized release
```

## Code Conventions

- **Language**: Zig 0.15.x
- **Formatting**: `zig fmt` defaults
- **Linting**: `zig fmt --check` (must pass)
- **Architecture**: lexer → parser → AST → builder → doc IR → printer
- **Dependencies**: None (Zig std only)

## Tests & CI

- **CI** (`test.yml`): Runs `make can-release` on ubuntu-24.04
- **Build** (`build.yml`): Multi-platform CLI builds
- Auto-updates `draft-release` branch after tests pass on main

## PR & Workflow Rules

- **Branches**: `main` for development, `draft-release` auto-updated from CI
- **CI gates**: All tests must pass before merge
- **Release**: Push to draft-release triggers build workflow

## Source Files

| File | Purpose |
|------|---------|
| `token.zig` | Token definitions and locations |
| `lexer.zig` | Tokenization |
| `parser.zig` | Pratt parser, AST construction |
| `ast.zig` | AST node definitions |
| `doc.zig` | Wadler-Lindig document primitives |
| `builder.zig` | AST to document IR conversion |
| `printer.zig` | Document IR to formatted string |
| `lib.zig` | Public library API |
| `main.zig` | CLI entry point |
| `formatter_test.zig` | Comprehensive test suite |

## Related Projects

| Project | Type | Path |
|---------|------|------|
| santa-lang | Language spec | `~/Projects/santa-lang` |
| santa-lang-comet | Interpreter (Rust) | `~/Projects/santa-lang-comet` |
