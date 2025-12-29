const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Interp = @import("../interp.zig");
const Dictionary = @import("../dictionary.zig");
const Info = @import("../dictionary.zig").Info;
const Index = Dictionary.Index;
const ExecutionToken = Dictionary.ExecutionToken;
const registerPrimitive = @import("core.zig").registerPrimitive;
const fetch = @import("mem.zig").fetch;

pub fn doCol(ctx: *Interp) !void {
    try ctx.return_stack.push(ctx.IP);
}

pub fn exit(ctx: *Interp) !void {
    const return_address = try ctx.return_stack.pop();
    ctx.IP = return_address;
}

pub fn doCreate(ctx: *Interp) !void {
    // pushes the address of the new word's parameters onto the data stack
    try ctx.data_stack.push(@intFromPtr(ctx.dict.data.items[ctx.IP..].ptr));
}

pub fn doDoes(ctx: *Interp) !void {
    // pushes the address of the does word's parameters onto the data stack
    // then jumps to the does code
    const does_code_index_usize = try ctx.dict.getParameter(Index.fromInt(ctx.IP), usize);
    const pfa_ptr = ctx.dict.data.items[ctx.IP + @sizeOf(usize) ..].ptr;
    try ctx.data_stack.push(@intFromPtr(pfa_ptr)); // this skips over the index to the code to execute
    // ensure the does code runs by pushing a return address and switching IP
    try ctx.return_stack.push(ctx.IP);
    ctx.IP = does_code_index_usize;
}

pub fn defineWord(ctx: *Interp) !void {
    const symbol = ctx.tokenizer.next().?;
    switch (symbol) {
        .symbol => |name| {
            _ = try ctx.dict.createWord(ctx.gpa);
            const info = Info{
                .name_length = @truncate(name.len),
                .smuged = true,
            };
            try ctx.dict.addInfo(ctx.gpa, info);
            try ctx.dict.addName(ctx.gpa, name);
            try ctx.dict.addExecutionToken(ctx.gpa, @intFromPtr(&doCol));
            ctx.mode = .Compile;
        },
        else => {
            return error.InvalidWordDefinition;
        },
    }
}

pub fn endDefinition(ctx: *Interp) !void {
    try ctx.dict.addParameter(ctx.gpa, usize, @intFromPtr(&exit));
    var info = try ctx.dict.getInfo(ctx.dict.last.add(Dictionary.INFO_OFFSET));
    info.smuged = false;
    try ctx.dict.setInfo(ctx.dict.last.add(Dictionary.INFO_OFFSET), info);
    ctx.mode = .Interpret;
}

pub fn create(ctx: *Interp) !void {
    const symbol = ctx.tokenizer.next().?;
    switch (symbol) {
        .symbol => |name| {
            _ = try ctx.dict.createWord(ctx.gpa);
            const info = Info{
                .name_length = @truncate(name.len),
            };
            try ctx.dict.addInfo(ctx.gpa, info);
            try ctx.dict.addName(ctx.gpa, name);
            try ctx.dict.addExecutionToken(ctx.gpa, @intFromPtr(&doCreate));
        },
        else => {
            return error.InvalidWordDefinition;
        },
    }
}

pub fn does(ctx: *Interp) !void {
    const word_index = ctx.dict.last;
    var info = try ctx.dict.getInfo(word_index.add(Dictionary.INFO_OFFSET));
    // if (!info.smuged) {
    //     return error.DoesRequiresCreate;
    // }
    // info.smuged = false;
    // try ctx.dict.setInfo(word_index.add(Dictionary.INFO_OFFSET), info);
    // Modify the execution token to point to doDoes
    const execution_token: ExecutionToken = @intFromPtr(&doDoes);
    const exec_token_index = word_index.add(info.nameEndOffset()).forward_aligned(@alignOf(usize));
    try ctx.dict.setExecutionToken(exec_token_index, execution_token);

    const param_index = exec_token_index.add(@sizeOf(usize));
    // The does code follows immediately in the caller's parameter stream (ctx.IP).
    // We will record the original start index of that does code as the parameter
    // on the created word, and then skip over it in the defining run.
    const does_code_start = ctx.IP;

    // Add a pointer to the original does-code start as a parameter
    try ctx.dict.addParameter(ctx.gpa, usize, does_code_start);

    // Reorder parameters so the does-code index is the first parameter
    const reordered_params_len = ctx.dict.head.toInt() - param_index.toInt();
    const tmp_buffer = try ctx.gpa.alloc(u8, reordered_params_len);
    // copy the last parameter (the does code index) to the front of tmp_buffer
    @memcpy(tmp_buffer[0..@sizeOf(usize)], ctx.dict.data.items[ctx.dict.head.toInt() - @sizeOf(usize) .. ctx.dict.head.toInt()]);
    // copy the rest of the parameters after that
    @memcpy(tmp_buffer[@sizeOf(usize)..], ctx.dict.data.items[param_index.toInt() .. ctx.dict.head.toInt() - @sizeOf(usize)]);
    // write back the reordered parameters
    @memcpy(ctx.dict.data.items[param_index.toInt() .. param_index.toInt() + reordered_params_len], tmp_buffer[0..reordered_params_len]);

    ctx.gpa.free(tmp_buffer);

    // End the defining run immediately by exiting the current inner loop.
    // This prevents the does-code from executing during the defining run; the
    // does-code remains at the recorded index so `doDoes` can jump there at runtime.
    try exit(ctx);
}

pub fn comma(ctx: *Interp) !void {
    const value = try ctx.data_stack.pop();
    try ctx.dict.addParameter(ctx.gpa, usize, value);
}

pub fn allot(ctx: *Interp) !void {
    const num_bytes = try ctx.data_stack.pop();
    const current_head = ctx.dict.head.toInt();
    const new_head = current_head + num_bytes;
    try ctx.dict.data.resize(ctx.gpa, new_head);
    ctx.dict.head = Index.fromInt(new_head);
}

// defining words

pub fn @"const"(ctx: *Interp) !void {
    try doCol(ctx);
    try create(ctx);
    try comma(ctx);
    try does(ctx);
}

pub fn @"var"(ctx: *Interp) !void {
    try doCol(ctx);
    try create(ctx);
    try ctx.data_stack.push(@sizeOf(usize));
    try allot(ctx);
    try exit(ctx);
}

pub fn addDefiningPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, ":", defineWord, true);
    try registerPrimitive(dict, gpa, ";", endDefinition, true);
    try registerPrimitive(dict, gpa, "CREATE", create, false);
    try registerPrimitive(dict, gpa, "DOES>", does, false);
    try registerPrimitive(dict, gpa, ",", comma, false);
    try registerPrimitive(dict, gpa, "ALLOT", allot, false);
    try registerPrimitive(dict, gpa, "CONST", @"const", false);
    try dict.addParameter(gpa, usize, @intFromPtr(&fetch));
    try dict.addParameter(gpa, usize, @intFromPtr(&exit));
    try registerPrimitive(dict, gpa, "VAR", @"var", false);
}
