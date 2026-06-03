const std = @import("std");
const common = @import("common");

// WASM has no OS allocator — use a static buffer as your heap
var heap: [10 * 1024 * 1024]u8 = undefined; // 64MB static heap
var fba = std.heap.FixedBufferAllocator.init(&heap);
const allocator = fba.allocator();

// Shared output buffer — JS reads from this after calling format()
var out_buf: [10 * 1024 * 1024]u8 = undefined;
var out_len: usize = 0;

// Expose a pointer for JS to write the input into
var in_buf: [10 * 1024 * 1024]u8 = undefined;

extern fn js_log(ptr: [*]const u8, len: usize) void;

fn log(msg: []const u8) void {
    js_log(msg.ptr, msg.len);
}

var out_buf_debug: [64]u8 = undefined;

// JS calls this to get a pointer to write input data into
export fn getInputPtr() [*]u8 {
    return &in_buf;
}

// JS calls this to get a pointer to read output data from
export fn getOutputPtr() [*]u8 {
    return &out_buf;
}

// JS calls this to get the output length after formatting
export fn getOutputLen() usize {
    return out_len;
}

// Reset allocator between calls — critical for long-running sessions
export fn reset() void {
    fba.reset();
    out_len = 0;
}

export fn formatJson(input_len: usize) i32 {
    fba.reset();

    const input = in_buf[0..input_len];
    log("format json called");
    log(input);
    common.wasm_wrapper(fba.allocator(), input, &out_buf, &out_len);
    const len_str = std.fmt.bufPrint(&out_buf_debug, "out_len={d}", .{out_len}) catch "?";
    log(len_str);
    return 0;
}
