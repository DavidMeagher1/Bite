const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const TextField = @This();

text: ArrayListUnmanaged(ArrayListUnmanaged(u8)) = .empty,

pub fn init() !TextField {
    const tf = TextField{
        .text = .empty,
    };
    return tf;
}

pub fn deinit(self: *TextField, gpa: Allocator) void {
    for (0..self.text.items.len) |i| {
        self.text.items[i].deinit(gpa);
    }
    self.text.deinit(gpa);
}

pub fn addLine(self: *TextField, gpa: Allocator, line: []const u8) !void {
    var new_line = ArrayListUnmanaged(u8).empty;
    try new_line.ensureTotalCapacity(gpa, line.len);
    for (line) |b| {
        _ = try new_line.append(gpa, b);
    }
    //_ = try new_line.appendSlice(gpa, line);
    try self.text.append(gpa, new_line);
}

pub fn getLine(self: *TextField, line_number: usize) ?*ArrayListUnmanaged(u8) {
    if (line_number >= self.text.items.len) {
        return null;
    }
    return &self.text.items[line_number];
}

pub fn removeLine(self: *TextField, gpa: Allocator, line_number: usize) !void {
    if (line_number >= self.text.items.len) {
        return error.LineNotFound;
    }
    var line = self.text.orderedRemove(line_number);
    line.deinit(gpa);
    return;
}

pub fn setLine(self: *TextField, gpa: Allocator, line_number: usize, line: []const u8) !void {
    if (line_number >= self.text.items.len) {
        return error.LineNotFound;
    }
    var target_line = &self.text.items[line_number];
    target_line.clearRetainingCapacity();
    for (line) |b| {
        _ = try target_line.append(gpa, b);
    }
    return;
}

pub fn lineCount(self: *TextField) usize {
    return self.text.items.len;
}

pub fn clear(self: *TextField, gpa: Allocator) void {
    for (0..self.text.items.len) |i| {
        self.text.items[i].deinit(gpa);
    }
    self.text.clearRetainingCapacity();
}

pub fn toOwnedSlice(self: *TextField, gpa: Allocator) ![][]u8 {
    var result = try gpa.alloc([]u8, self.text.items.len);
    for (self.text.items, 0..) |line, i| {
        const line_slice = try line.toOwnedSlice(gpa);
        result[i] = line_slice;
    }
    self.deinit(gpa);
    return result;
}

pub fn toFlattened(self: *TextField, gpa: Allocator) ![]u8 {
    var total_len: usize = 0;
    for (self.text.items) |line| {
        total_len += line.items.len; // +1 for separator
    }
    if (total_len == 0) {
        return &[]u8{};
    }
    var result = try gpa.alloc(u8, total_len);
    var position: usize = 0;
    for (self.text.items) |line| {
        @memcpy(result[position .. position + line.items.len], line.items);
        position += line.items.len;
        line.deinit(gpa);
    }
    self.deinit(gpa);
    return result;
}

pub fn writeLines(self: *TextField, writer: anytype, numbered: bool) !void {
    var line_number: usize = 1;
    for (self.text.items) |line| {
        if (numbered) {
            try writer.print("  {d}: {s}", .{ line_number, line.items[0..line.items.len] });
        } else {
            _ = try writer.write(line.items[0..line.items.len]);
            _ = try writer.write("\n");
        }
        line_number += 1;
    }
}
