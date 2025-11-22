const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Stack = @This();
const Type = @import("type.zig");

const Error = error{
    StackUnderflow,
    StackOverflow,
} || Allocator.Error;

bounds: union(enum) {
    dynamic: void,
    fixed: usize,
} = .dynamic,
items: ArrayListUnmanaged(Type.Cell) = .empty,

pub fn initSized(gpa: Allocator, initial_size: ?usize) !Stack {
    var result = Stack{};
    if (initial_size) |size| {
        result.bounds = .{ .fixed = size };
        try result.items.ensureTotalCapacity(gpa, size);
    } else {
        result.bounds = .dynamic;
    }
    return result;
}

pub inline fn init(gpa: Allocator) !Stack {
    return Stack.initSized(gpa, null);
}

pub fn deinit(self: *Stack, gpa: Allocator) void {
    self.items.deinit(gpa);
    self.bounds = .dynamic;
}

pub fn sp(self: *Stack) usize {
    return self.items.items.len;
}

pub fn within_bounds(self: *Stack, position: usize) bool {
    return switch (self.bounds) {
        .dynamic => true,
        .fixed => position < self.items.items.len,
    };
}

pub fn push(self: *Stack, gpa: Allocator, value: Type.Cell) Error!void {
    if (!self.within_bounds(self.sp() + 1)) {
        return Error.StackOverflow;
    }
    switch (self.bounds) {
        .dynamic => {
            try self.items.append(gpa, value);
        },
        .fixed => {
            self.items.appendAssumeCapacity(value);
        },
    }
}

pub fn pop(self: *Stack) Error!Type.Cell {
    if (self.sp() == 0) {
        return Error.StackUnderflow;
    }
    return self.items.pop() orelse unreachable;
}

pub fn peek(self: *Stack) ?Type.Cell {
    if (self.sp() == 0) {
        return null;
    }
    return self.items.items[self.sp() - 1];
}
