const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Info = @import("../dictionary.zig").Info;
const Interp = @import("../interp.zig");
const Dictionary = @import("../dictionary.zig");
const Index = Dictionary.Index;
const ExecutionToken = Dictionary.ExecutionToken;
pub const PrimitiveFunction = *const fn (ctx: *Interp) anyerror!void;

pub fn registerPrimitive(
    dict: *Dictionary,
    gpa: Allocator,
    name: []const u8,
    fn_ptr: PrimitiveFunction,
    immediate: bool,
) !void {
    const info = Info{
        .name_length = @truncate(name.len),
        .immediate = immediate,
    };

    _ = try dict.createWord(gpa);
    try dict.addInfo(gpa, info);
    try dict.addName(gpa, name);
    const execution_token: ExecutionToken = @intFromPtr(fn_ptr);
    try dict.addExecutionToken(gpa, execution_token);
}

pub fn goto(ctx: *Interp) !void {
    const target = try ctx.dict.getParameter(Index.fromInt(ctx.IP), usize);
    ctx.IP = target;
}

pub fn lparen(ctx: *Interp) !void {
    const stored_seek = ctx.tokenizer.seek - 1; // include the '('
    var token = ctx.tokenizer.next();
    while (token != null) {
        switch (token.?) {
            .symbol => |sym| {
                if (mem.eql(u8, sym, ")")) {
                    ctx.tokenizer._needs_input = false;
                    return;
                }
            },
            else => {},
        }
        token = ctx.tokenizer.next();
    }
    ctx.tokenizer.seek = stored_seek;
    ctx.tokenizer._needs_input = true;
    return error.UnterminatedComment;
}

pub fn addCorePrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, "(", lparen, true);
}
