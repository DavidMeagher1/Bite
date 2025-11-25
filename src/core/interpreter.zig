const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const mem = std.mem;
const Allocator = mem.Allocator;
const Interpreter = @This();
const Dictionary = @import("dictionary.zig");
const Type = @import("type.zig");
const Lexer = @import("lexer.zig");
const Stack = @import("stack.zig");
const primitives = @import("primitives.zig");

pub const Mode = enum {
    interpreting,
    compiling,
};

pub const Error = error{
    InvalidAddress,
    EndOfCode,
    UnknownWord,
} || Stack.Error || Dictionary.Error;

pub const InterpreterOptions = struct {
    stack_size: ?usize = null,
};

gpa: Allocator,
inner: InnerInterpreter = .{},
lexer: Lexer = undefined,
IP: Type.Address = 0,
C: Type.CodeIndex = 0,
dictionary: Dictionary = .{},
mode: Mode = .interpreting,
data_stack: Stack = .{},
return_stack: Stack = .{},

const InnerInterpreter = struct {
    const Error = error{
        InvalidAddress,
    };
    // Executes a word at the given address
    halted: bool = false,

    pub fn exec(outer: *Interpreter, cidx: Type.CodeIndex) !void {
        const instr = InnerInterpreter.fetch(outer, cidx) orelse return error.InvalidAddress;
        try instr(outer);
    }

    pub fn step(outer: *Interpreter) !bool {
        // assume current IP points to a CodeIndex
        const func_bytes = outer.dictionary.data.items[outer.IP .. outer.IP + @sizeOf(Type.CodeIndex)];
        const func_addr: Type.CodeIndex = std.mem.bytesToValue(Type.CodeIndex, func_bytes);
        const func:Type.Instruction = @ptrFromInt(func_addr);
        outer.IP += @sizeOf(Type.Address); // advance past the address
        try func(outer);
        return !outer.inner.halted;
    }

    pub fn run(outer: *Interpreter) !void {
        while (true) {
            const continue_running = try InnerInterpreter.step(outer);
            if (!continue_running) {
                outer.inner.halted = false; // reset halted state for next run
                break;
            }
        }
    }
};

pub fn init(gpa: Allocator, options: InterpreterOptions) !Interpreter {
    const data_stack = try Stack.initSized(gpa, options.stack_size);
    const return_stack = try Stack.initSized(gpa, options.stack_size);
    var result = Interpreter{
        .gpa = gpa,
        .inner = undefined,
        .data_stack = data_stack,
        .return_stack = return_stack,
    };
    try primitives.register_defaults(&result);
    return result;
}

pub fn deinit(self: *Interpreter) void {
    self.dictionary.deinit(self.gpa);
    self.data_stack.deinit(self.gpa);
    self.return_stack.deinit(self.gpa);
    self.IP = 0;
}

pub fn load(self: *Interpreter, source: [:0]const u8) Error!void {
    self.lexer.reset(source);
    return;
}

pub fn step(self: *Interpreter) !void {
    const value = self.lexer.next();
    switch (value) {
        .eoi => return error.EndOfCode,
        .text => |text| {
            // Handle text token
            const widx = self.dictionary.findWord(text);
            if (widx) |idx| {
                const info = self.dictionary.getWordInfo(idx) orelse return error.InvalidAddress;
                if (self.mode == .interpreting or info.flags.immediate) {
                    self.IP = idx + info.getCodeOffset();
                    const addr_bytes = self.dictionary.data.items[self.IP .. self.IP + @sizeOf(Type.Address)];
                    const addr: Type.CodeIndex = std.mem.bytesToValue(Type.CodeIndex, addr_bytes);
                    if (addr == @intFromPtr(&primitives.docol)) {
                        // we are executing a user-defined word
                        self.IP += @sizeOf(Type.Address); // advance past docol
                    }
                    try self.return_stack.push(self.gpa, Type.Constants.sentinel_return_address); // push sentinel
                    try InnerInterpreter.run(self);
                } else {
                    const cfa = idx + info.getCodeOffset();
                    const addr_bytes = self.dictionary.data.items[cfa .. cfa + @sizeOf(Type.Address)];
                    const addr: Type.CodeIndex = std.mem.bytesToValue(Type.CodeIndex, addr_bytes);
                    if (addr == @intFromPtr(&primitives.docol)){
                        // we are compiling a user-defined word
                        self.dictionary.here += try self.dictionary.addCode(self.gpa, @intFromPtr(&primitives.execute));
                        self.dictionary.here += try self.dictionary.addData(self.gpa, cfa + @sizeOf(Type.Address));
                    } else {
                        // we are compiling a primitive
                        self.dictionary.here += try self.dictionary.addCode(self.gpa, addr);
                    }
                }
            } else {
                return error.UnknownWord;
            }
        },
        .s_int, .u_int => {
            if (self.mode == .interpreting) {
                // Push the literal onto the data stack
                switch (value) {
                    .s_int => |v_int| {
                        try self.data_stack.push(self.gpa, @bitCast(v_int));
                    },
                    .u_int => |v_int| {
                        try self.data_stack.push(self.gpa, @bitCast(v_int));
                    },
                    else => unreachable,
                }
            } else {
                // Compile a LITERAL instruction followed by the value
                self.dictionary.here += try self.dictionary.addData(self.gpa, @intFromPtr(&primitives.literal)); // compile LITERAL instruction
                switch (value) {
                    .s_int => |v_int| {
                        self.dictionary.here += try self.dictionary.addData(self.gpa, @bitCast(v_int));
                    },
                    .u_int => |v_int| {
                        self.dictionary.here += try self.dictionary.addData(self.gpa, @bitCast(v_int));
                    },
                    else => unreachable,
                }
            }
        },
    }
}

pub fn run(self: *Interpreter) !void {
    while (true) {
        self.step() catch |err| {
            if (err == error.EndOfCode) break;
            return err;
        };
    }
    return;
}

pub fn register_primitive(self: *Interpreter, name: []const u8, func: Type.Instruction, is_immediate: bool) !void {
    // inaccessable primitive
    // accessable primtive
    try self.dictionary.startWord(self.gpa);
    const info = Dictionary.WordInfo{
        .flags = .{
            .immediate = is_immediate,
        },
        .name_len = @truncate(name.len),
    };
    self.dictionary.here += try self.dictionary.addWordInfo(self.gpa, info);
    self.dictionary.here += try self.dictionary.addName(self.gpa, name[0..@as(u5, @truncate(name.len))]);
    self.dictionary.here += try self.dictionary.addCode(self.gpa, @intFromPtr(func));
    self.dictionary.here += try self.dictionary.addData(self.gpa, @intFromPtr(&primitives.doexit));
}

test "unknown word" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load("FOOBAR");
    const result = interpreter.run();
    try std.testing.expectEqual(result, error.UnknownWord);
}

test "simple addition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load("10 14 +");
    try interpreter.run();
    const top = try interpreter.data_stack.pop();
    try std.testing.expectEqual(24, top);
}

test "word definition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load(": add-2 2 + ; 10 add-2");
    try interpreter.run();
    const top = try interpreter.data_stack.pop();
    try std.testing.expectEqual(12, top);
}

test "literal in a word" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load(": foo LITERAL 99 ; foo");
    try interpreter.run();
    const top = try interpreter.data_stack.pop();
    try std.testing.expectEqual(99, top);
}

test "word in a word" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load(": foo LITERAL 10 ; : bar foo  ; bar");
    try interpreter.run();
    const top = try interpreter.data_stack.pop();
    try std.testing.expectEqual(10, top);
}

test "create and does" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load(": test CREATE DOES> 10 ; test foo foo");
    try interpreter.run();
    const top = try interpreter.data_stack.pop();
    try std.testing.expectEqual( 10, top);
}

test "drop test"{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load("42 DROP");
    try interpreter.run();
    const sp = interpreter.data_stack.sp();
    try std.testing.expectEqual(0, sp);
}

test "Constant" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    try interpreter.load(": CONSTANT CREATE , DOES> @ ; 42 CONSTANT foo foo");
    try interpreter.run();
    const top = try interpreter.data_stack.pop();
    try std.testing.expectEqual(42, top);
}