const std = @import("std");
const common = @import("common");
const Mode = enum { auto, pipe, pty };
const c = @cImport({
    @cInclude("pty.h");
    @cInclude("unistd.h");
    @cInclude("poll.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/wait.h");
});

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var mode: Mode = .auto;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--pipe")) mode = .pipe;
        if (std.mem.eql(u8, arg, "--pty")) mode = .pty;
    }

    const use_pty = switch (mode) {
        .auto => try std.Io.File.stdin().isTty(init.io),
        .pipe => false,
        .pty => true,
    };

    if (use_pty) {
        try runAsPty();
    } else {
        try readFromPipe(init.io, init.arena.allocator());
    }
}

fn readFromPipe(io: std.Io, allocator: std.mem.Allocator) !void {
    var stdin_buf: [4096]u8 = undefined;

    var accumulator: std.ArrayList(u8) = .empty;
    defer accumulator.deinit(allocator);

    const stdin_file = std.Io.File.stdin();
    var stdin_reader = stdin_file.readerStreaming(io, &stdin_buf);
    while (true) {
        const bytes_read = try stdin_reader.interface.readSliceShort(&stdin_buf);
        if (bytes_read == 0) break;
        try accumulator.appendSlice(allocator, stdin_buf[0..bytes_read]);
    }
    const input = accumulator.items;

    var stdout_buf: [4096]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writerStreaming(io, &stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    try common.prettify(allocator, input, stdout);

    try stdout.flush();
}

fn runAsPty() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    // 1. open PTY pair
    var master_fd: c_int = undefined;
    var slave_fd: c_int = undefined;
    if (c.openpty(&master_fd, &slave_fd, null, null, null) != 0) {
        return error.OpenPtyFailed;
    }

    // 2. fork
    const pid = c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        // --- child: become the shell ---
        _ = c.close(master_fd);
        _ = c.setsid();

        // make slave the controlling terminal
        _ = c.ioctl(slave_fd, c.TIOCSCTTY, @as(c_int, 0));

        // wire slave to stdin/stdout/stderr
        _ = c.dup2(slave_fd, c.STDIN_FILENO);
        _ = c.dup2(slave_fd, c.STDOUT_FILENO);
        _ = c.dup2(slave_fd, c.STDERR_FILENO);
        _ = c.close(slave_fd);

        var argv = [_][*c]u8{ @constCast("bash"), null };
        _ = c.execvp("bash", &argv);

        // only reached if exec fails
        _ = c.write(c.STDERR_FILENO, "exec failed\n", 12);
        std.process.exit(1);
    }

    // --- parent: intercept loop ---
    _ = c.close(slave_fd);

    var fds = [_]c.struct_pollfd{
        .{ .fd = c.STDIN_FILENO, .events = c.POLLIN, .revents = 0 },
        .{ .fd = master_fd, .events = c.POLLIN, .revents = 0 },
    };

    var buf: [4096]u8 = undefined;

    while (true) {
        _ = arena.reset(.retain_capacity);
        const ready = c.poll(&fds, 2, -1);
        if (ready < 0) break;

        // keystrokes → shell
        if (fds[0].revents & c.POLLIN != 0) {
            const n = c.read(c.STDIN_FILENO, &buf, buf.len);
            if (n <= 0) break;
            _ = c.write(master_fd, &buf, @intCast(n));
        }

        // shell output → process → terminal
        if (fds[1].revents & c.POLLIN != 0) {
            const n = c.read(master_fd, &buf, buf.len);
            if (n <= 0) break;
            const chunk = buf[0..@intCast(n)];
            if (isEscapeSequence(chunk)) {
                _ = c.write(c.STDOUT_FILENO, chunk.ptr, chunk.len);
            } else {
                const processed = process(buf[0..@intCast(n)], allocator);
                // TODO: figure out the byte output/extra stuff being output
                std.debug.print("processed {any}\n", .{processed});
                _ = c.write(c.STDOUT_FILENO, processed.ptr, processed.len);
            }
        }
    }

    // wait for shell to exit
    _ = c.waitpid(pid, null, 0);
}

fn process(chunk: []const u8, allocator: std.mem.Allocator) []const u8 {
    // TODO: Switch fixed buffer
    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    common.prettify(allocator, chunk, &writer) catch return chunk;

    const written = allocator.dupe(u8, buf[0..writer.end]) catch return chunk;
    return written;
}

fn isEscapeSequence(chunk: []const u8) bool {
    return chunk.len > 0 and chunk[0] == 27; // ESC byte
}
