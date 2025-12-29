const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const Error = error{
    StackOverflow,
    StackUnderflow,
};

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        items: []T,
        top: usize,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            return Self{
                .items = try allocator.alloc(T, capacity),
                .top = 0,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.items);
            self.items = &[_]T{};
            self.top = 0;
        }

        pub fn reset(self: *Self) void {
            self.top = 0;
        }

        pub fn push(self: *Self, value: T) Error!void {
            if (self.top >= self.items.len) {
                return error.StackOverflow;
            }
            self.items[self.top] = value;
            self.top += 1;
        }

        pub fn pop(self: *Self) Error!T {
            if (self.top == 0) {
                return error.StackUnderflow;
            }
            self.top -= 1;
            const value = self.items[self.top];
            return value;
        }

        pub fn peek(self: *const Self) Error!T {
            if (self.top == 0) {
                return error.StackUnderflow;
            }
            return self.items[self.top - 1];
        }
    };
}
