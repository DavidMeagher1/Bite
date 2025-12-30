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

pub fn subtract(ctx: *Interp) !void {
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.pop();
    try ctx.data_stack.push(a - b);
}

pub fn multiply(ctx: *Interp) !void {
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.pop();
    try ctx.data_stack.push(a * b);
}

pub fn divide(ctx: *Interp) !void {
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.pop();
    if (b == 0) {
        try ctx.data_stack.push(a);
        try ctx.data_stack.push(b);
        return error.DivideByZero;
    }
    try ctx.data_stack.push(a / b);
}

pub fn modulo(ctx: *Interp) !void {
    const b = try ctx.data_stack.pop();
    const a = try ctx.data_stack.pop();
    if (b == 0) {
        try ctx.data_stack.push(a);
        try ctx.data_stack.push(b);
        return error.DivideByZero;
    }
    try ctx.data_stack.push(a % b);
}

pub fn addMathPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, "+", add, false);
    try registerPrimitive(dict, gpa, "-", subtract, false);
    try registerPrimitive(dict, gpa, "*", multiply, false);
    try registerPrimitive(dict, gpa, "/", divide, false);
    try registerPrimitive(dict, gpa, "%", modulo, false);
}
