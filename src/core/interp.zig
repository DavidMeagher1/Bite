const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Dictionary = @import("dictionary.zig");
const Index = Dictionary.Index;
const Tokenizer = @import("tokenizer.zig");
const primitives = @import("primitives.zig");
const PrimitiveFunction = primitives.PrimitiveFunction;
const Stack = @import("stack.zig").Stack;

const Interp = @This();

const Mode = enum {
    Interpret,
    Compile,
};

gpa: Allocator,
reader: std.io.Reader,
IP: usize = 0,
dict: Dictionary,
tokenizer: Tokenizer,
mode: Mode = .Interpret,
data_stack: Stack(usize),
return_stack: Stack(usize),

pub fn init(
    gpa: Allocator,
    reader: std.io.Reader,
) !Interp {
    return Interp{
        .gpa = gpa,
        .reader = reader,
        .IP = 0,
        .dict = .{},
        .tokenizer = .{ .buffer = undefined },
        .mode = .Interpret,
        .data_stack = try Stack(usize).init(gpa, 256),
        .return_stack = try Stack(usize).init(gpa, 256),
    };
}

pub fn deinit(self: *Interp) void {
    self.tokenizer.deinit(self.gpa);
    self.dict.deinit(self.gpa);
    self.data_stack.deinit(self.gpa);
    self.return_stack.deinit(self.gpa);
}

fn innerLoop(self: *Interp) !void {
    while (true) {
        const param = try self.dict.getParameter(Index.fromInt(self.IP), usize);
        const fn_ptr: PrimitiveFunction = @ptrFromInt(param);
        self.IP += @sizeOf(usize);
        try fn_ptr(self);
        if (self.return_stack.top == 0) {
            break;
        }
    }
}

pub fn next(self: *Interp) !bool {
    var token = self.tokenizer.next();
    if (token == null) {
        try self.tokenizer.load(self.gpa, &self.reader, 1024);
        token = self.tokenizer.next();
        if (token == null) {
            return false;
        }
    }
    switch (token.?) {
        .symbol => |sym| {
            const word_index = try self.dict.getWord(sym);
            const info = try self.dict.getInfo(word_index.add(Dictionary.INFO_OFFSET));
            switch (self.mode) {
                .Interpret => {
                    const index = word_index.add(info.nameEndOffset()).forward_aligned(@alignOf(usize));
                    self.IP = index.toInt();
                    // next inner loop to execute the word
                    try self.innerLoop();
                },

                .Compile => {
                    if (info.immediate) {
                        const index = word_index.add(info.nameEndOffset()).forward_aligned(@alignOf(usize));
                        self.IP = index.toInt();
                        // next inner loop to execute the immediate word
                        try self.innerLoop();
                    } else {
                        const index = word_index.add(info.nameEndOffset()).forward_aligned(@alignOf(usize));
                        const fn_ptr_addr = try self.dict.getExecutionToken(index);
                        const fn_ptr: PrimitiveFunction = @ptrFromInt(fn_ptr_addr);
                        if (fn_ptr == primitives.doCol) {
                            // Compile a call to the colon definition
                            try self.dict.addParameter(self.gpa, usize, @intFromPtr(&primitives.goto));
                            try self.dict.addParameter(self.gpa, usize, index.toInt());
                        } else {
                            // Compile the primitive function address directly
                            try self.dict.addParameter(self.gpa, usize, fn_ptr_addr);
                        }
                    }
                },
            }
        },

        .number => |num| {
            switch (self.mode) {
                .Interpret => {
                    try self.data_stack.push(num);
                },
                .Compile => {
                    try self.dict.addParameter(self.gpa, usize, @intFromPtr(&primitives.lit));
                    try self.dict.addParameter(self.gpa, usize, num);
                },
            }
        },
    }
    return true;
}

pub fn run(self: *Interp) !void {
    while (true) {
        const has_more = try self.next();
        if (!has_more) {
            break;
        }
    }
}

test "Interp init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var buffer: [1024]u8 = undefined;
    const reader: std.io.Reader = std.io.Reader.fixed(&buffer);
    var interp = try Interp.init(allocator, reader);
    interp.deinit();
}

test "Interp next with empty input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var buffer: [1024]u8 = mem.zeroes([1024]u8);
    const reader: std.io.Reader = std.io.Reader.fixed(&buffer);
    var interp = try Interp.init(allocator, reader);
    _ = try interp.next();
    interp.deinit();
}

test "Interp next with single number" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const buffer: []const u8 = "42";
    const reader: std.io.Reader = std.io.Reader.fixed(buffer);
    var interp = try Interp.init(allocator, reader);
    _ = try interp.next();
    const value = try interp.data_stack.pop();
    try std.testing.expect(value == 42);
    interp.deinit();
}

test "Interp with addition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const buffer: []const u8 = "10 32 +";
    const reader: std.io.Reader = std.io.Reader.fixed(buffer);
    var interp = try Interp.init(allocator, reader);
    try primitives.addPrimitiveFunctions(&interp.dict, allocator);
    try interp.run();
    const result = try interp.data_stack.pop();
    try std.testing.expect(result == 42);
    interp.deinit();
}

test "Interp with literal in compile mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const buffer: []const u8 = ": TEST LITERAL 99 ; TEST";
    const reader: std.io.Reader = std.io.Reader.fixed(buffer);
    var interp = try Interp.init(allocator, reader);
    try primitives.addPrimitiveFunctions(&interp.dict, allocator);
    try interp.run();
    const value = try interp.data_stack.pop();
    try std.testing.expect(value == 99);
    interp.deinit();
}

test "Interp add2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const buffer: []const u8 = ": ADD2 LITERAL 2 + ; 40 ADD2";
    const reader: std.io.Reader = std.io.Reader.fixed(buffer);
    var interp = try Interp.init(allocator, reader);
    try primitives.addPrimitiveFunctions(&interp.dict, allocator);
    try interp.run();
    const result = try interp.data_stack.pop();
    try std.testing.expect(result == 42);
    interp.deinit();
}

test "simple DOES> CREATE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const buffer: []const u8 = ": CONST CREATE , DOES> @ ; 33 CONST MYCONST MYCONST";
    const reader: std.io.Reader = std.io.Reader.fixed(buffer);
    var interp = try Interp.init(allocator, reader);
    try primitives.addPrimitiveFunctions(&interp.dict, allocator);
    try interp.run();
    const value = try interp.data_stack.pop();
    try std.testing.expect(value == 33);
    interp.deinit();
}

test "DOES> not executed at definition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const buffer: []const u8 = ": CONST CREATE , DOES> @ ; 33 CONST MYCONST";
    const reader: std.io.Reader = std.io.Reader.fixed(buffer);
    var interp = try Interp.init(allocator, reader);
    try primitives.addPrimitiveFunctions(&interp.dict, allocator);
    try interp.run();
    try std.testing.expect(interp.data_stack.top == 0);
    interp.deinit();
}
