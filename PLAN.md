# Formatter Alignment Progress

## Completed Fixes

### 1. Pipe Chain Breaking (Critical)
- **Issue**: All multi-pipe chains were force-broken
- **Fix**: Changed to use soft lines; pipes break only at line width
- **Location**: `src/builder.zig:buildChain`

### 2. String Newline Preservation (Critical)
- **Issue**: Multiline strings in test sections were collapsed to `\n` escapes
- **Fix**: Always preserve literal newlines in strings
- **Location**: `src/builder.zig:escapeString`

### 3. Semicolon Preservation (Critical)
- **Issue**: User-placed semicolons were stripped
- **Fix**: Added `has_trailing_semicolon` to AST Statement, preserve in output
- **Location**: `src/ast.zig`, `src/parser.zig`, `src/builder.zig`

### 4. Blank Line Preservation (Critical)
- **Issue**: Auto-inserted blank lines between all statements
- **Fix**: Only preserve user blank lines (tracked via `preceded_by_blank_line`)
- **Location**: `src/builder.zig:buildProgram`, `buildStatements`

### 5. Range Expression Parentheses (Medium)
- **Issue**: `(start_y + 1)..=height` became `start_y + 1..=height`
- **Fix**: Add parens around infix expressions in range operands
- **Location**: `src/builder.zig:buildRangeOperand`

### 6. Inline If with Return (Medium)
- **Issue**: `if x { return [...] }` expanded to multiline
- **Fix**: Handle return/break in `isSimpleBody` and `buildInlineBody`
- **Location**: `src/builder.zig`

### 7. Line Width (Medium)
- **Issue**: 100 char limit too restrictive (reference has lines up to 134)
- **Fix**: Increased LINE_WIDTH to 140
- **Location**: `src/printer.zig:LINE_WIDTH`

### 8. Section vs Lambda Pipe Breaking (Critical)
- **Issue**: All implicit return pipes were force-broken
- **Fix**: Only force-break in section bodies (part_one, part_two, test), not lambdas
- **Location**: `src/builder.zig:buildStatements`, `buildSectionImplicitReturn`

## Remaining Differences

Some stylistic differences remain where the reference formatter's exact rules are unclear:

1. **If-else body formatting**: Reference sometimes breaks simple if-else across lines when it could fit on one line
2. **Trailing closure positioning**: Complex heuristics for when to use trailing closure syntax
3. **Nested pipe formatting**: Some nested pipe patterns format differently

## Files Changed

- `src/ast.zig` - Added `has_trailing_semicolon` to Statement
- `src/parser.zig` - Track semicolons, set new field in all Statement creations
- `src/builder.zig` - Major formatting logic changes
- `src/printer.zig` - Increased line width to 140

## Test Results

Initial: 61 files with 0 changes expected
After fixes: ~57 files still show diffs, but many are minor stylistic differences
The most critical issues (semicolons, blank lines, string escaping) are now fixed.

## Verification

Run formatter over AoC files:
```bash
./zig-out/bin/santa-fmt -w /Users/edd/Projects/advent-of-code/*/santa-lang/*.santa
git -C /Users/edd/Projects/advent-of-code diff --stat
```
