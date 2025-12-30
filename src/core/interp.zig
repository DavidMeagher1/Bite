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

const InterpOptions = struct {
    stack_capacity: usize = 256,
    control_stack_capacity: usize = 64,
};

const Mode = enum {
    Interpret,
    Compile,
};

gpa: Allocator,
IP: usize = 0,
dict: Dictionary,
tokenizer: Tokenizer,
mode: Mode = .Interpret,
data_stack: Stack(usize),
return_stack: Stack(usize),
control_stack: Stack(usize),

pub fn init(
    gpa: Allocator,
    options: InterpOptions,
) !Interp {
    var result = Interp{
        .gpa = gpa,
        .IP = 0,
        .dict = .{},
        .tokenizer = .{ .buffer = undefined },
        .mode = .Interpret,
        .data_stack = try Stack(usize).init(gpa, options.stack_capacity),
        .return_stack = try Stack(usize).init(gpa, options.stack_capacity),
        .control_stack = try Stack(usize).init(gpa, options.control_stack_capacity),
    };
    try primitives.addPrimitives(&result.dict, gpa);
    result.dict.mark();
    return result;
}

pub fn deinit(self: *Interp) void {
    self.tokenizer.deinit(self.gpa);
    self.dict.deinit(self.gpa);
    self.data_stack.deinit(self.gpa);
    self.return_stack.deinit(self.gpa);
    self.control_stack.deinit(self.gpa);
}

fn innerLoop(self: *Interp) !void {
    while (true) {
        const param = try self.dict.getExecutionToken(Index.fromInt(self.IP));
        const fn_ptr: PrimitiveFunction = @ptrFromInt(param);
        self.IP += @sizeOf(usize);
        try fn_ptr(self);
        if (self.return_stack.top == 0) {
            break;
        }
    }
}

pub fn next(self: *Interp) !bool {
    const token = self.tokenizer.next();
    if (token == null) {
        return false;
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
                        if (fn_ptr == primitives.defining.doCol) {
                            // Compile a call to the colon definition
                            try self.dict.addParameter(self.gpa, usize, @intFromPtr(&primitives.core.goto));
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
                    try self.dict.addParameter(self.gpa, usize, @intFromPtr(&primitives.stack.lit));
                    try self.dict.addParameter(self.gpa, usize, num);
                },
            }
        },
    }
    return true;
}

pub fn run(self: *Interp, code: []const u8) !void {
    try self.tokenizer.load(self.gpa, code);
    while (true) {
        const has_more = try self.next();
        if (!has_more) {
            break;
        }
    }
}

pub fn feed(self: *Interp, code: []const u8) !void {
    try self.tokenizer.append(self.gpa, code);
    while (true) {
        const has_more = try self.next();
        if (!has_more) {
            break;
        }
    }
}

pub fn reset(self: *Interp) void {
    self.tokenizer.reset();
    self.mode = .Interpret;
    self.data_stack.reset();
    self.return_stack.reset();
    self.control_stack.reset();
    self.IP = 0;
}

test "Interp init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var interp = try Interp.init(allocator, .{});
    interp.deinit();
}

test "Interp next with empty input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var interp = try Interp.init(allocator, .{});
    _ = try interp.next();
    interp.deinit();
}

test "Interp next with single number" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const buffer: []const u8 = "42";
    var interp = try Interp.init(allocator, .{});
    try interp.tokenizer.load(allocator, buffer);
    _ = try interp.next();
    const value = try interp.data_stack.pop();
    try std.testing.expect(value == 42);
    interp.deinit();
}

test "Interp with addition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const buffer: []const u8 = "10 32 +";
    var interp = try Interp.init(allocator, .{});
    try interp.run(buffer);
    const result = try interp.data_stack.pop();
    try std.testing.expect(result == 42);
    interp.deinit();
}

test "Interp with literal in compile mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var dbg = std.heap.DebugAllocator(.{}){};
    defer _ = dbg.deinit();
    const allocator = dbg.allocator();
    const buffer: []const u8 = ": TEST LITERAL 99 ; TEST";
    var interp = try Interp.init(allocator, .{});
    try interp.run(buffer);
    const value = try interp.data_stack.pop();
    try std.testing.expect(value == 99);
    interp.deinit();
}

test "Interp add2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const buffer: []const u8 = ": ADD2 LITERAL 2 + ; 40 ADD2";
    var interp = try Interp.init(allocator, .{});
    try interp.run(buffer);
    const result = try interp.data_stack.pop();
    try std.testing.expect(result == 42);
    interp.deinit();
}

test "simple DOES> CREATE" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const buffer: []const u8 = "33 CONST MYCONST MYCONST";
    var interp = try Interp.init(allocator, .{});
    try interp.run(buffer);
    const value = try interp.data_stack.pop();
    try std.testing.expect(value == 33);
    interp.deinit();
}

test "DOES> not executed at definition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const buffer: []const u8 = "33 CONST MYCONST";
    var interp = try Interp.init(allocator, .{});
    try interp.run(buffer);
    try std.testing.expect(interp.data_stack.top == 0);
    interp.deinit();
}
