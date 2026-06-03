const std = @import("std");

const State = enum {
    object_expect_key,
    object_expect_value,
    array_element,
};

pub fn wasm_wrapper(allocator: std.mem.Allocator, raw_json: []const u8, output_buffer: []u8, out_len: *usize) void {
    var writer = std.Io.Writer.fixed(output_buffer);
    prettify(allocator, raw_json, &writer) catch return;
    out_len.* = writer.buffered().len;
    writer.flush() catch return;
}

pub fn prettify(allocator: std.mem.Allocator, raw_json: []const u8, writer: *std.Io.Writer) !void {
    if (raw_json.len == 0) {
        return;
    }
    var scanner = std.json.Scanner.initCompleteInput(allocator, raw_json);
    defer scanner.deinit();

    var indent_level: usize = 0;
    var is_first_item = true;

    var stack: std.ArrayList(State) = .empty;
    defer stack.deinit(allocator);

    while (true) {
        const token = try scanner.next();
        if (token == .end_of_document) break;

        // 1. Handle Closing Brackets (Dedent before emitting formatting structural markers)
        switch (token) {
            .object_end, .array_end => {
                _ = stack.pop();
                indent_level -= 1;
                try writer.writeByte('\n');
                try writer.splatByteAll(' ', indent_level * 4);
                is_first_item = false;
            },
            else => {},
        }

        // 2. Handle Entry Spacing, Commas, and Colons
        if (stack.items.len > 0) {
            const current_state = stack.items[stack.items.len - 1];

            switch (token) {
                // Bracket structures handle their indentation lines uniquely
                .object_end, .array_end => {},

                else => {
                    if (current_state == .object_expect_value) {
                        // We just read a key string, now write out the separating colon
                        try writer.writeAll(": ");
                    } else {
                        // We are about to print a new Key or an Array Element
                        if (!is_first_item) {
                            try writer.writeAll(",\n");
                        }
                        try writer.splatByteAll(' ', indent_level * 4);
                        is_first_item = false;
                    }
                },
            }
        }

        // 3. Render the exact Token Content and advance the state layout
        switch (token) {
            .object_begin => {
                try writer.writeAll("{\n");
                indent_level += 1;
                try stack.append(allocator, .object_expect_key);
                is_first_item = true;
            },
            .array_begin => {
                try writer.writeAll("[\n");
                indent_level += 1;
                try stack.append(allocator, .array_element);
                is_first_item = true;
            },
            .object_end => try writer.writeByte('}'),
            .array_end => try writer.writeByte(']'),

            .string => |slice| {
                try writer.print("\"{s}\"", .{slice});

                // Toggle state inside an object
                if (stack.items.len > 0) {
                    const top = &stack.items[stack.items.len - 1];
                    if (top.* == .object_expect_key) {
                        top.* = .object_expect_value;
                    } else if (top.* == .object_expect_value) {
                        top.* = .object_expect_key;
                    }
                }
            },

            .number, .partial_number, .allocated_number => |slice| {
                try writer.writeAll(slice);
                if (stack.items.len > 0) {
                    const top = &stack.items[stack.items.len - 1];
                    if (top.* == .object_expect_value) top.* = .object_expect_key;
                }
            },

            .true => {
                try writer.writeAll("true");
                if (stack.items.len > 0) {
                    const top = &stack.items[stack.items.len - 1];
                    if (top.* == .object_expect_value) top.* = .object_expect_key;
                }
            },
            .false => {
                try writer.writeAll("false");
                if (stack.items.len > 0) {
                    const top = &stack.items[stack.items.len - 1];
                    if (top.* == .object_expect_value) top.* = .object_expect_key;
                }
            },
            .null => {
                try writer.writeAll("null");
                if (stack.items.len > 0) {
                    const top = &stack.items[stack.items.len - 1];
                    if (top.* == .object_expect_value) top.* = .object_expect_key;
                }
            },

            else => {},
        }
    }
    try writer.writeByte('\n');
}
