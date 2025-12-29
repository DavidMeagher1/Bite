const std = @import("std");
const Allocator = std.mem.Allocator;

pub const core = @import("primitives/core.zig");
pub const PrimitiveFunction = core.PrimitiveFunction;
pub const registerPrimitive = core.registerPrimitive;

pub const defining = @import("primitives/defining.zig");
pub const math = @import("primitives/math.zig");
pub const mem = @import("primitives/mem.zig");
pub const meta = @import("primitives/meta.zig");
pub const stack = @import("primitives/stack.zig");
pub const Dictionary = @import("dictionary.zig");

pub fn addPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try core.addCorePrimitives(dict, gpa);
    try defining.addDefiningPrimitives(dict, gpa);
    try math.addMathPrimitives(dict, gpa);
    try mem.addMemPrimitives(dict, gpa);
    try meta.addMetaPrimitives(dict, gpa);
    try stack.addStackPrimitives(dict, gpa);
}
