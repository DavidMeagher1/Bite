const std = @import("std");
const Interpreter = @import("interpreter.zig");
pub const Address = usize;
pub const Cell = usize;
pub const CodeIndex = usize;
pub const WordIndex = usize;
pub const Instruction = *const fn (interpreter: *Interpreter) anyerror!void;

pub const Constants = struct {
    pub const sentinel_return_address: Address = std.math.maxInt(Address);
    pub const max_word_name_length: u5 = std.math.maxInt(u5);
};
