const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Interp = @import("../interp.zig");
const PrimitiveFunction = @import("core.zig").PrimitiveFunction;
const Dictionary = @import("../dictionary.zig");
const Index = Dictionary.Index;
const registerPrimitive = @import("core.zig").registerPrimitive;

pub fn literal(ctx: *Interp) !void {
    switch (ctx.mode) {
        .Interpret => {
            const num = ctx.tokenizer.next() orelse return error.ExpectedNumber;
            switch (num) {
                .number => |n| {
                    try ctx.data_stack.push(n);
                },
                else => {
                    return error.ExpectedNumber;
                },
            }
        },
        .Compile => {
            try ctx.dict.addParameter(ctx.gpa, PrimitiveFunction, lit);
            const num = ctx.tokenizer.next() orelse return error.ExpectedNumber;
            switch (num) {
                .number => |n| {
                    try ctx.dict.addParameter(ctx.gpa, usize, n);
                },
                else => {
                    return error.ExpectedNumber;
                },
            }
        },
    }
}

pub fn lit(ctx: *Interp) !void {
    const num = try ctx.dict.getParameter(Index.fromInt(ctx.IP), usize);
    ctx.IP += @sizeOf(usize);
    try ctx.data_stack.push(num);
}

pub fn drop(ctx: *Interp) !void {
    _ = try ctx.data_stack.pop();
}

pub fn dup(ctx: *Interp) !void {
    const value = try ctx.data_stack.peek();
    try ctx.data_stack.push(value);
}

pub fn swap(ctx: *Interp) !void {
    const a = try ctx.data_stack.pop();
    const b = try ctx.data_stack.pop();
    try ctx.data_stack.push(a);
    try ctx.data_stack.push(b);
}

pub fn over(ctx: *Interp) !void {
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.peek();
    try ctx.data_stack.push(b);
    try ctx.data_stack.push(a);
}

pub fn nip(ctx: *Interp) !void {
    const a = try ctx.data_stack.pop();
    _ = try ctx.data_stack.pop();
    try ctx.data_stack.push(a);
}

pub fn rot(ctx: *Interp) !void {
    const c = try ctx.data_stack.pop();
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.pop();
    try ctx.data_stack.push(b);
    try ctx.data_stack.push(c);
    try ctx.data_stack.push(a);
}

pub fn toR(ctx: *Interp) !void {
    const value = try ctx.data_stack.pop();
    try ctx.return_stack.push(value);
}

pub fn addStackPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, "LITERAL", literal, true);
    try registerPrimitive(dict, gpa, "DROP", drop, false);
    try registerPrimitive(dict, gpa, "DUP", dup, false);
    try registerPrimitive(dict, gpa, "SWAP", swap, false);
    try registerPrimitive(dict, gpa, "OVER", over, false);
    try registerPrimitive(dict, gpa, "NIP", nip, false);
    try registerPrimitive(dict, gpa, "ROT", rot, false);
    try registerPrimitive(dict, gpa, ">R", toR, false);
}
