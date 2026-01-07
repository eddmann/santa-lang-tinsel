const std = @import("std");
const build_options = @import("build_options");
const lib = @import("lib");

const usage =
    \\Usage: santa-fmt [options] [file]
    \\
    \\Options:
    \\  -f, --fmt          Format to stdout (default)
    \\  -w, --fmt-write    Format in place
    \\  -c, --fmt-check    Check if formatted (exit 1 if not)
    \\  -e <expr>          Format expression from argument
    \\  -v, --version      Display version information
    \\  -h, --help         Show this help message
    \\
    \\If no file is specified, reads from stdin.
    \\
;

const Mode = enum {
    format_stdout,
    format_write,
    format_check,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var mode: Mode = .format_stdout;
    var file_path: ?[]const u8 = null;
    var expr_source: ?[]const u8 = null;

    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage);
            return;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "santa-fmt {s}\n", .{build_options.version}) catch unreachable;
            try stdout.writeAll(msg);
            return;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--fmt")) {
            mode = .format_stdout;
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--fmt-write")) {
            mode = .format_write;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--fmt-check")) {
            mode = .format_check;
        } else if (std.mem.eql(u8, arg, "-e")) {
            i += 1;
            if (i >= args.len) {
                try stderr.writeAll("Error: -e requires an argument\n");
                std.process.exit(1);
            }
            expr_source = args[i];
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            file_path = arg;
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    // Get source
    const source: []const u8 = if (expr_source) |expr|
        expr
    else if (file_path) |path|
        try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024)
    else blk: {
        // Read from stdin
        var stdin = std.fs.File.stdin();
        break :blk try stdin.readToEndAlloc(allocator, 10 * 1024 * 1024);
    };
    defer if (file_path != null or expr_source == null) allocator.free(source);

    // Format
    const formatted = lib.format(allocator, source) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(formatted);

    switch (mode) {
        .format_stdout => {
            try stdout.writeAll(formatted);
        },
        .format_write => {
            if (file_path) |path| {
                try std.fs.cwd().writeFile(.{
                    .sub_path = path,
                    .data = formatted,
                });
            } else {
                try stderr.writeAll("Error: --fmt-write requires a file path\n");
                std.process.exit(1);
            }
        },
        .format_check => {
            if (std.mem.eql(u8, formatted, source)) {
                // Already formatted
                std.process.exit(0);
            } else {
                // Needs formatting
                if (file_path) |path| {
                    std.debug.print("{s}: not formatted\n", .{path});
                } else {
                    try stderr.writeAll("stdin: not formatted\n");
                }
                std.process.exit(1);
            }
        },
    }
}
