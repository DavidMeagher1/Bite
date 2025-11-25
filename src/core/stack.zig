const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Stack = @This();
const Type = @import("type.zig");

pub const Error = error{
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

pub fn dup(self: *Stack, gpa: Allocator) Error!void {
    const value = self.peek() orelse return Error.StackUnderflow;
    try self.push(gpa, value);
}

pub fn swap(self: *Stack) Error!void {
    if (self.sp() < 2) {
        return Error.StackUnderflow;
    }
    const top_index = self.sp() - 1;
    const second_index = self.sp() - 2;
    const top_value = self.items.items[top_index];
    const second_value = self.items.items[second_index];
    self.items.items[top_index] = second_value;
    self.items.items[second_index] = top_value;
}

pub fn over(self: *Stack, gpa: Allocator) Error!void {
    if (self.sp() < 2) {
        return Error.StackUnderflow;
    }
    const second_index = self.sp() - 2;
    const second_value = self.items.items[second_index];
    try self.push(gpa, second_value);
}

pub fn rot(self: *Stack) Error!void {
    if (self.sp() < 3) {
        return Error.StackUnderflow;
    }
    const top_index = self.sp() - 1;
    const second_index = self.sp() - 2;
    const third_index = self.sp() - 3;
    const top_value = self.items.items[top_index];
    const second_value = self.items.items[second_index];
    const third_value = self.items.items[third_index];
    self.items.items[third_index] = second_value;
    self.items.items[second_index] = top_value;
    self.items.items[top_index] = third_value;
}

pub fn rev_rot(self: *Stack) Error!void {
    if (self.sp() < 3) {
        return Error.StackUnderflow;
    }
    const top_index = self.sp() - 1;
    const second_index = self.sp() - 2;
    const third_index = self.sp() - 3;
    const top_value = self.items.items[top_index];
    const second_value = self.items.items[second_index];
    const third_value = self.items.items[third_index];
    self.items.items[third_index] = top_value;
    self.items.items[second_index] = third_value;
    self.items.items[top_index] = second_value;
}

pub fn nip(self: *Stack) Error!void {
    if (self.sp() < 2) {
        return Error.StackUnderflow;
    }
    try self.swap();
    _ = try self.pop();
}

pub fn tuck(self: *Stack, gpa: Allocator) Error!void {
    if (self.sp() < 2) {
        return Error.StackUnderflow;
    }
    try self.dup(gpa);   // duplicate top
    try self.rot();      // rotate third to top
}

pub fn drop2(self: *Stack) Error!void {
    if (self.sp() < 2) {
        return Error.StackUnderflow;
    }
    _ = try self.pop();
    _ = try self.pop();
}

pub fn dup2(self: *Stack, gpa: Allocator) Error!void {
    if (self.sp() < 2) {
        return Error.StackUnderflow;
    }
    const top_index = self.sp() - 1;
    const second_index = self.sp() - 2;
    const top_value = self.items.items[top_index];
    const second_value = self.items.items[second_index];
    try self.push(gpa, second_value);
    try self.push(gpa, top_value);
}

pub fn swap2(self: *Stack) Error!void {
    if (self.sp() < 4) {
        return Error.StackUnderflow;
    }
    const top1_index = self.sp() - 1;
    const top2_index = self.sp() - 2;
    const second1_index = self.sp() - 3;
    const second2_index = self.sp() - 4;
    const top1_value = self.items.items[top1_index];
    const top2_value = self.items.items[top2_index];
    const second1_value = self.items.items[second1_index];
    const second2_value = self.items.items[second2_index];
    self.items.items[second2_index] = top2_value;
    self.items.items[second1_index] = top1_value;
    self.items.items[top2_index] = second2_value;
    self.items.items[top1_index] = second1_value;
}

pub fn over2(self: *Stack, gpa: Allocator) Error!void {
    if (self.sp() < 4) {
        return Error.StackUnderflow;
    }
    const second2_index = self.sp() - 4;
    const second2_value = self.items.items[second2_index];
    try self.push(gpa, second2_value);
}