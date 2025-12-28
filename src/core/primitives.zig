const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Dictionary = @import("dictionary.zig").Dictionary;
const ExecutionToken = Dictionary.ExecutionToken;
const Info = Dictionary.Info;

const PrimitiveFunction = *const fn (ctx: *anyopaque) anyerror!void;

pub fn registerPrimitive(
    dict: *Dictionary,
    gpa: Allocator,
    name: []const u8,
    fn_ptr: PrimitiveFunction,
) !void {
    const info = Info{
        .name_length = @truncate(name.len),
        .flags = .Primitive,
    };

    _ = try dict.addWordStart(gpa);
    try dict.addInfo(gpa, info);
    try dict.addName(gpa, name);
    const execution_token: ExecutionToken = @intFromPtr(fn_ptr);
    try dict.addExecutionToken(gpa, execution_token);
}
