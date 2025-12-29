const std = @import("std");
const mem = std.mem;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const bite = @import("Bite");
const TextField = @import("textfield.zig");
// trying to make a REPL
var exit: bool = false;
var recording: bool = false;
var inputed_code: TextField = undefined;
var out_buffer: [1024]u8 = undefined;
var stdout: std.fs.File = undefined;
var in_buffer: [1024]u8 = undefined;
var stdin: std.fs.File = undefined;
var code_buffer: [4096]u8 = undefined;

fn cls(ctx: *bite.interp) !void {
    _ = ctx;
    var writer = stdout.writer(&out_buffer);
    _ = try writer.interface.write("\x1b[2J\x1b[H");
    try writer.interface.flush();
    return error.DEBUG;
}

fn start_recording(ctx: *bite.interp) !void {
    _ = ctx;
    recording = true;
    return error.DEBUG;
}
fn stop_recording(ctx: *bite.interp) !void {
    _ = ctx;
    recording = false;
    return error.DEBUG;
}

fn write_stacks(ctx: *bite.interp) !void {
    var writer = stdout.writer(&out_buffer);
    // print stack
    try print_stack(ctx.data_stack, &writer.interface);
    _ = try writer.interface.write("----------------------------------------\n");
    try print_stack(ctx.return_stack, &writer.interface);
    try writer.interface.flush();
    return error.DEBUG;
}

fn quit(ctx: *bite.interp) !void {
    // set some flag to exit the main loop
    // for now, just do nothing
    _ = ctx;
    exit = true;
}

fn reset(ctx: *bite.interp) !void {
    ctx.reset();
    //inputed_code.clear(ctx.gpa);
    try ctx.dict.resetToMark(ctx.gpa);
    return error.DEBUG;
}

fn resetStacks(ctx: *bite.interp) !void {
    ctx.data_stack.reset();
    ctx.return_stack.reset();
    return error.DEBUG;
}

fn listCode(ctx: *bite.interp) !void {
    // for now, just do nothing
    _ = ctx;
    var writer = stdout.writer(&code_buffer);
    _ = try writer.interface.write("---\n");
    try inputed_code.writeLines(&writer.interface, true);
    _ = try writer.interface.write("---\n");
    try writer.interface.flush();
    return error.DEBUG;
}

fn saveCode(ctx: *bite.interp) !void {
    // for now, just do nothing
    const token = ctx.tokenizer.next();
    if (token) |t| {
        switch (t) {
            .symbol => |sym| {
                var file = try std.fs.cwd().createFile(sym, .{
                    .truncate = true,
                });
                defer file.close();
                var buffer: [1024]u8 = undefined;
                var writer = file.writer(&buffer);
                try inputed_code.writeLines(&writer.interface, false);
                try writer.interface.flush();
            },
            else => {
                return error.InvalidArgument;
            },
        }
    } else {
        return error.InvalidArgument;
    }
    return error.DEBUG;
}

pub fn loadCode(ctx: *bite.interp) !void {
    const token = ctx.tokenizer.next();
    if (token) |t| {
        switch (t) {
            .symbol => |sym| {
                var file = try std.fs.cwd().openFile(sym, .{ .mode = .read_only });
                defer file.close();
                var buffer: [1024]u8 = undefined;
                var reader = file.reader(&buffer);
                while (true) {
                    const line = reader.interface.takeDelimiterInclusive('\n') catch |e| {
                        if (e == error.EndOfStream) {
                            break;
                        } else {
                            return e;
                        }
                    };
                    try inputed_code.addLine(ctx.gpa, line);
                }
            },
            else => {
                return error.InvalidArgument;
            },
        }
    } else {
        return error.InvalidArgument;
    }
    return error.DEBUG;
}

fn replayCode(ctx: *bite.interp) !void {
    ctx.reset();
    for (inputed_code.text.items) |line| {
        try ctx.run(line.items);
    }
    write_stacks(ctx) catch |e| {
        if (e != error.DEBUG) {
            return e;
        }
    };
    return error.DEBUG;
}

fn editLine(ctx: *bite.interp) !void {
    const line_num = try ctx.data_stack.pop();
    if (line_num == 0 or line_num > inputed_code.lineCount()) {
        return error.LineNotFound;
    }
    const actual_line_num = line_num - 1;
    var line: *ArrayListUnmanaged(u8) = inputed_code.getLine(actual_line_num).?;
    var token = ctx.tokenizer.next();
    line.clearRetainingCapacity();
    while (token != null) {
        switch (token.?) {
            .symbol => |sym| {
                _ = try line.appendSlice(ctx.gpa, sym);
            },
            .number => |num| {
                var num_buffer: [32]u8 = undefined;
                const num_str = try std.fmt.bufPrint(&num_buffer, "{any}", .{num});
                _ = try line.appendSlice(ctx.gpa, num_str);
            },
        }
        token = ctx.tokenizer.next();
        if (token != null) {
            _ = try line.append(ctx.gpa, ' ');
        }
    }
    try line.append(ctx.gpa, '\n');
    return error.DEBUG;
}

fn removeLine(ctx: *bite.interp) !void {
    const line_num = try ctx.data_stack.pop();
    if (line_num == 0 or line_num > inputed_code.lineCount()) {
        return error.LineNotFound;
    }
    try inputed_code.removeLine(ctx.gpa, line_num - 1);
    return error.DEBUG;
}

pub fn main() !void {
    stdout = std.fs.File.stdout();
    stdin = std.fs.File.stdin();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    defer inputed_code.deinit(allocator);
    //const stderr = std.fs.File.stderr();
    var writer = stdout.writer(&out_buffer);
    var reader = stdin.reader(&in_buffer);

    var interp = try bite.interp.init(allocator, .{
        .stack_capacity = 256,
        .control_stack_capacity = 64,
    });
    defer interp.deinit();
    try bite.primitives.addPrimitiveFunctions(&interp.dict, allocator);
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        "cls",
        &cls,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".R",
        &start_recording,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".!R",
        &stop_recording,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        "QUIT",
        &quit,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        "RESET",
        &reset,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        "RESET-STACKS",
        &resetStacks,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".LIST",
        &write_stacks,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".?",
        &listCode,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".\\",
        &editLine,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".-",
        &removeLine,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".++",
        &replayCode,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".S",
        &saveCode,
        false,
    );
    try bite.primitives.registerPrimitive(
        &interp.dict,
        allocator,
        ".L",
        &loadCode,
        false,
    );
    interp.dict.mark();
    outer_loop: while (!exit) {
        try writer.interface.print("> ", .{});
        try writer.interface.flush();
        const input = reader.interface.takeDelimiterInclusive('\n') catch |e| {
            if (e == error.EndOfStream) {
                continue;
            } else {
                return e;
            }
        };
        interp.run(input) catch |e| {
            if (e == error.UnterminatedComment) {
                if (recording) {
                    try inputed_code.addLine(allocator, input);
                }

                while (true) {
                    try writer.interface.print("\\> ", .{});
                    try writer.interface.flush();
                    const more = try reader.interface.takeDelimiterInclusive('\n');
                    interp.feed(more) catch |ee| {
                        if (ee == error.UnterminatedComment) {
                            if (recording) {
                                try inputed_code.addLine(allocator, more);
                            }
                            continue;
                        } else {
                            return ee;
                        }
                    };
                    if (recording) {
                        try inputed_code.addLine(allocator, more);
                    }
                    if (!interp.tokenizer._needs_input) {
                        continue :outer_loop;
                    }
                }
            }
            if (e == error.DEBUG) {
                // continue to get more input
                continue;
            }
            try writer.interface.print("{}\n", .{e});
            continue;
        };
        if (recording) {
            try inputed_code.addLine(allocator, input);
        }
        write_stacks(&interp) catch |e| {
            if (e != error.DEBUG) {
                return e;
            }
        };
        try writer.interface.flush();
    }
}

fn print_stack(stack: anytype, writer: *std.io.Writer) !void {
    if (stack.top == 0) {
        try writer.print("_\n", .{});
        return;
    }
    const items = stack.items[0..stack.top];
    var buffer: [256]u8 = undefined;
    for (items) |value| {
        const bytes = try std.fmt.bufPrint(&buffer, "{any} ", .{value});
        _ = try writer.write(bytes);
    }
    writer.writeByte('\n') catch {};
}
