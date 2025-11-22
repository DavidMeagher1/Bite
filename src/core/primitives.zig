const std = @import("std");
const Type = @import("type.zig");
const Interpreter = @import("interpreter.zig");

pub fn docol(self: *Interpreter) !void {
    self.IP += @sizeOf(Type.WordIndex);
    try self.return_stack.push(self.gpa, self.IP); // store the address of the next instruction to execute
}

pub fn exit(self: *Interpreter) !void {
    const return_address = self.return_stack.pop() catch |err| {
        self.inner.halted = true;
        return err;
    };
    const is_sentinel = return_address == Interpreter.sentinal_return_address;
    if (is_sentinel) {
        self.inner.halted = true;
        return;
    }
    self.IP = return_address;
}

pub fn add(interp: *Interpreter) !void {
    const b: Type.Cell = try interp.data_stack.pop();
    const a: Type.Cell = try interp.data_stack.pop();
    try interp.data_stack.push(interp.gpa, a + b);
    try exit(interp);
}

pub fn debug_print(interp: *Interpreter) !void {
    const value: Type.Cell = try interp.data_stack.pop();
    std.debug.print("Top of stack: {d}\n", .{value});
    try exit(interp);
}

pub fn register_defaults(interp: *Interpreter) !void {
    try interp.register_primitive("+", add, false);
    try interp.register_primitive(".", debug_print, false);
}
