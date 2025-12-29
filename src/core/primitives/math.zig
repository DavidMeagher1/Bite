const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Interp = @import("../interp.zig");
const Dictionary = @import("../dictionary.zig");
const registerPrimitive = @import("core.zig").registerPrimitive;
pub fn add(ctx: *Interp) !void {
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.pop();
    try ctx.data_stack.push(a + b);
}

pub fn addMathPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, "+", add, false);
}
