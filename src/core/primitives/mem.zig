const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Interp = @import("../interp.zig");
const Dictionary = @import("../dictionary.zig");
const registerPrimitive = @import("core.zig").registerPrimitive;

pub fn fetch(ctx: *Interp) !void {
    const address = try ctx.data_stack.pop();
    const value_ptr: *const usize = @ptrFromInt(address);
    const value = value_ptr.*;
    try ctx.data_stack.push(value);
}

pub fn store(ctx: *Interp) !void {
    const value = try ctx.data_stack.pop();
    const address = try ctx.data_stack.pop();
    const value_ptr: *usize = @ptrFromInt(address);
    value_ptr.* = value;
}

pub fn addMemPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, "@", fetch, false);
    try registerPrimitive(dict, gpa, "!", store, false);
}
