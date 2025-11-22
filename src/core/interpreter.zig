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

const Mode = enum {
    interpreting,
    compiling,
};

const Error = error{
    InvalidAddress,
    EndOfCode,
};

const InterpreterOptions = struct {
    stack_size: ?usize = null,
};

pub const sentinal_return_address: Type.Address = std.math.maxInt(Type.Address);

gpa: Allocator,
inner: InnerInterpreter = .{},
lexer: Lexer = undefined,
IP: Type.Address = 0,
dictionary: Dictionary = .{},
code_address_list: ArrayListUnmanaged(Type.Address) = .empty,
mode: Mode = .interpreting,
data_stack: Stack = .{},
return_stack: Stack = .{},

const InnerInterpreter = struct {
    const Error = error{
        InvalidAddress,
    };
    // Executes a word at the given address
    halted: bool = false,

    pub fn fetch(outer: *Interpreter, cidx: Type.CodeIndex) ?Type.Instruction {
        if (cidx >= outer.code_address_list.items.len) {
            return null;
        }
        const instr_addr: Type.Address = outer.code_address_list.items[cidx];
        const instr: Type.Instruction = @ptrFromInt(instr_addr);
        return instr;
    }

    pub fn exec(outer: *Interpreter, cidx: Type.CodeIndex) !void {
        const instr = InnerInterpreter.fetch(outer, cidx) orelse return error.InvalidAddress;
        try instr(outer);
    }

    pub fn step(outer: *Interpreter) !bool {
        const widx: Type.WordIndex = outer.IP;
        const info = outer.dictionary.getWordInfo(widx) orelse return error.InvalidAddress;
        const cidx = outer.dictionary.getCode(widx) orelse return error.InvalidAddress;
        outer.IP += info.getDataOffset();
        try InnerInterpreter.exec(outer, cidx);
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
    try result.code_address_list.appendSlice(gpa, &[_]Type.Address{ @intFromPtr(&primitives.docol), @intFromPtr(&primitives.exit) }); // add docol, and next addresses as initial code
    try primitives.register_defaults(&result);
    return result;
}

pub fn deinit(self: *Interpreter) void {
    self.dictionary.deinit(self.gpa);
    self.code_address_list.deinit(self.gpa);
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
            if (self.mode == .interpreting) {
                // Look up the word in the dictionary and execute it
                const widx = self.dictionary.findWord(text);
                if (widx) |idx| {
                    self.IP = idx;
                    try self.return_stack.push(self.gpa, sentinal_return_address); // push a sentinel return address
                    try InnerInterpreter.run(self);
                } else {
                    return error.InvalidAddress;
                }
            } else {
                // Compile the word into the current definition
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
                // Compile a literal instruction followed by the value
            }
        },
    }
}

pub fn getCodeIndex(self: *Interpreter, address: Type.Address) ?Type.CodeIndex {
    return mem.indexOf(Type.Address, self.code_address_list.items, &[_]Type.Address{address});
}

pub fn register_primitive(self: *Interpreter, name: []const u8, func: Type.Instruction, is_immediate: bool) !void {
    try self.dictionary.startWord(self.gpa);
    self.dictionary.here += try self.dictionary.addWordInfo(self.gpa, .{
        .flags = .{
            .immediate = is_immediate,
        },
        .name_len = @truncate(name.len),
    });
    self.dictionary.here += try self.dictionary.addName(self.gpa, name[0..@as(u5, @truncate(name.len))]);
    const code_idx = self.code_address_list.items.len;
    self.dictionary.here += try self.dictionary.addCode(self.gpa, code_idx);
    try self.code_address_list.append(self.gpa, @intFromPtr(func));
}

test "simple test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = try Interpreter.init(allocator, .{});
    defer interpreter.deinit();

    const code = "10 14 + .";
    try interpreter.load(code);
    while (true) {
        interpreter.step() catch |err| {
            if (err == error.EndOfCode) break;
            return err;
        };
    }

    // Further tests would go here
}
