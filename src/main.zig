const std = @import("std");
const build_options = @import("build_options");
const lib = @import("lib");

const usage =
    \\usage: santa-tinsel [flags] [path ...]
    \\
    \\Flags:
    \\  -d    display diffs instead of rewriting files
    \\  -l    list files whose formatting differs from santa-tinsel's
    \\  -w    write result to (source) file instead of stdout
    \\  -h    display this help and exit
    \\  -v    display version and exit
    \\
    \\Without flags, santa-tinsel prints reformatted sources to stdout.
    \\Without path, santa-tinsel reads from stdin.
    \\Given a directory, santa-tinsel recursively processes all .santa files.
    \\
;

const Mode = enum {
    format_stdout, // default: print to stdout
    format_write, // -w: write to file
    list_diff, // -l: list files that differ
    show_diff, // -d: show diffs
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var mode: Mode = .format_stdout;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);

    const stdout_file = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h")) {
            try stdout_file.writeAll(usage);
            return;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            try stdout_file.writeAll("santa-lang Tinsel " ++ build_options.version ++ "\n");
            return;
        } else if (std.mem.eql(u8, arg, "-d")) {
            mode = .show_diff;
        } else if (std.mem.eql(u8, arg, "-l")) {
            mode = .list_diff;
        } else if (std.mem.eql(u8, arg, "-w")) {
            mode = .format_write;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            try paths.append(allocator, arg);
        } else {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "santa-tinsel: unknown flag: {s}\n", .{arg}) catch unreachable;
            try stderr_file.writeAll(msg);
            try stderr_file.writeAll("usage: santa-tinsel [flags] [path ...]\n");
            std.process.exit(2);
        }
    }

    // No paths: read from stdin
    if (paths.items.len == 0) {
        if (mode == .format_write) {
            try stderr_file.writeAll("santa-tinsel: cannot use -w with stdin\n");
            std.process.exit(2);
        }
        try processStdin(allocator, mode, stdout_file, stderr_file);
        return;
    }

    // Process each path
    var any_diff = false;
    for (paths.items) |path| {
        const stat = std.fs.cwd().statFile(path) catch |err| {
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ path, @errorName(err) }) catch unreachable;
            try stderr_file.writeAll(msg);
            std.process.exit(1);
        };

        if (stat.kind == .directory) {
            // Recursively process directory
            const had_diff = try processDirectory(allocator, path, mode, stdout_file, stderr_file);
            if (had_diff) any_diff = true;
        } else {
            // Process single file
            const had_diff = try processFile(allocator, path, mode, stdout_file, stderr_file);
            if (had_diff) any_diff = true;
        }
    }

    // Exit 1 if any files differed (for -l mode, useful for CI)
    if (mode == .list_diff and any_diff) {
        std.process.exit(1);
    }
}

fn processStdin(allocator: std.mem.Allocator, mode: Mode, stdout_file: std.fs.File, stderr_file: std.fs.File) !void {
    const stdin = std.fs.File.stdin();
    const source = try stdin.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(source);

    const formatted = lib.format(allocator, source) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "santa-tinsel: <stdin>: {s}\n", .{@errorName(err)}) catch unreachable;
        try stderr_file.writeAll(msg);
        std.process.exit(1);
    };
    defer allocator.free(formatted);

    switch (mode) {
        .format_stdout => try stdout_file.writeAll(formatted),
        .format_write => unreachable, // checked earlier
        .list_diff => {
            if (!std.mem.eql(u8, formatted, source)) {
                try stdout_file.writeAll("<stdin>\n");
                std.process.exit(1);
            }
        },
        .show_diff => {
            if (!std.mem.eql(u8, formatted, source)) {
                try printDiff(allocator, source, formatted, "<stdin>", stdout_file);
            }
        },
    }
}

fn processFile(allocator: std.mem.Allocator, path: []const u8, mode: Mode, stdout_file: std.fs.File, stderr_file: std.fs.File) !bool {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch |err| {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ path, @errorName(err) }) catch unreachable;
        try stderr_file.writeAll(msg);
        return false;
    };
    defer allocator.free(source);

    const formatted = lib.format(allocator, source) catch |err| {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ path, @errorName(err) }) catch unreachable;
        try stderr_file.writeAll(msg);
        return false;
    };
    defer allocator.free(formatted);

    const differs = !std.mem.eql(u8, formatted, source);

    switch (mode) {
        .format_stdout => try stdout_file.writeAll(formatted),
        .format_write => {
            if (differs) {
                std.fs.cwd().writeFile(.{
                    .sub_path = path,
                    .data = formatted,
                }) catch |err| {
                    var buf: [512]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ path, @errorName(err) }) catch unreachable;
                    try stderr_file.writeAll(msg);
                    return false;
                };
            }
        },
        .list_diff => {
            if (differs) {
                var buf: [4096]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{s}\n", .{path}) catch unreachable;
                try stdout_file.writeAll(msg);
            }
        },
        .show_diff => {
            if (differs) {
                try printDiff(allocator, source, formatted, path, stdout_file);
            }
        },
    }

    return differs;
}

fn processDirectory(allocator: std.mem.Allocator, dir_path: []const u8, mode: Mode, stdout_file: std.fs.File, stderr_file: std.fs.File) !bool {
    var any_diff = false;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ dir_path, @errorName(err) }) catch unreachable;
        try stderr_file.writeAll(msg);
        return false;
    };
    defer dir.close();

    var walker = dir.walk(allocator) catch |err| {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ dir_path, @errorName(err) }) catch unreachable;
        try stderr_file.writeAll(msg);
        return false;
    };
    defer walker.deinit();

    while (walker.next() catch |err| {
        var buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "santa-tinsel: {s}: {s}\n", .{ dir_path, @errorName(err) }) catch unreachable;
        try stderr_file.writeAll(msg);
        return any_diff;
    }) |entry| {
        if (entry.kind != .file) continue;

        // Check for .santa extension
        if (!std.mem.endsWith(u8, entry.basename, ".santa")) continue;

        // Skip hidden files
        if (std.mem.startsWith(u8, entry.basename, ".")) continue;

        // Build full path
        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        defer allocator.free(full_path);

        const had_diff = try processFile(allocator, full_path, mode, stdout_file, stderr_file);
        if (had_diff) any_diff = true;
    }

    return any_diff;
}

fn printDiff(allocator: std.mem.Allocator, original: []const u8, formatted: []const u8, filename: []const u8, file: std.fs.File) !void {
    // Simple line-by-line diff output (unified diff style header)
    var buf: [4096]u8 = undefined;

    var msg = std.fmt.bufPrint(&buf, "diff {s} {s}\n", .{ filename, filename }) catch unreachable;
    try file.writeAll(msg);
    msg = std.fmt.bufPrint(&buf, "--- {s}\n", .{filename}) catch unreachable;
    try file.writeAll(msg);
    msg = std.fmt.bufPrint(&buf, "+++ {s}\n", .{filename}) catch unreachable;
    try file.writeAll(msg);

    // Split into lines
    var orig_lines: std.ArrayList([]const u8) = .empty;
    defer orig_lines.deinit(allocator);
    var fmt_lines: std.ArrayList([]const u8) = .empty;
    defer fmt_lines.deinit(allocator);

    var orig_iter = std.mem.splitScalar(u8, original, '\n');
    while (orig_iter.next()) |line| {
        try orig_lines.append(allocator, line);
    }

    var fmt_iter = std.mem.splitScalar(u8, formatted, '\n');
    while (fmt_iter.next()) |line| {
        try fmt_lines.append(allocator, line);
    }

    // Simple diff: show all changes
    const max_lines = @max(orig_lines.items.len, fmt_lines.items.len);
    var line_num: usize = 1;
    var i: usize = 0;

    while (i < max_lines) : (i += 1) {
        const orig_line = if (i < orig_lines.items.len) orig_lines.items[i] else null;
        const fmt_line = if (i < fmt_lines.items.len) fmt_lines.items[i] else null;

        if (orig_line) |ol| {
            if (fmt_line) |fl| {
                if (!std.mem.eql(u8, ol, fl)) {
                    msg = std.fmt.bufPrint(&buf, "@@ -{d} +{d} @@\n", .{ line_num, line_num }) catch unreachable;
                    try file.writeAll(msg);
                    msg = std.fmt.bufPrint(&buf, "-{s}\n", .{ol}) catch unreachable;
                    try file.writeAll(msg);
                    msg = std.fmt.bufPrint(&buf, "+{s}\n", .{fl}) catch unreachable;
                    try file.writeAll(msg);
                }
            } else {
                msg = std.fmt.bufPrint(&buf, "@@ -{d} @@\n", .{line_num}) catch unreachable;
                try file.writeAll(msg);
                msg = std.fmt.bufPrint(&buf, "-{s}\n", .{ol}) catch unreachable;
                try file.writeAll(msg);
            }
        } else if (fmt_line) |fl| {
            msg = std.fmt.bufPrint(&buf, "@@ +{d} @@\n", .{line_num}) catch unreachable;
            try file.writeAll(msg);
            msg = std.fmt.bufPrint(&buf, "+{s}\n", .{fl}) catch unreachable;
            try file.writeAll(msg);
        }

        line_num += 1;
    }
}
