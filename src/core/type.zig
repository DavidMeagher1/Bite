const Interpreter = @import("interpreter.zig");
pub const Address = usize;
pub const Cell = usize;
pub const CodeIndex = usize;
pub const WordIndex = usize;
pub const Instruction = *const fn (interpreter: *Interpreter) anyerror!void;
