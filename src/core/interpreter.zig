const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const mem = std.mem;
const Allocator = mem.Allocator;
const Interpreter = @This();
const Dictionary = @import("dictionary.zig");
const Type = @import("type.zig");
const Lexer = @import("lexer.zig");

const Mode = enum {
    interpreting,
    compiling,
};

const Error = error{
    InvalidAddress,
    EndOfCode,
} || Dictionary.Error || Lexer.Error;

gpa: Allocator,
inner: InnerInterpreter,
lexer: Lexer = undefined,
IP: Type.Address = 0,
dictionary: Dictionary = .{},
code_address_list: ArrayListUnmanaged(Type.Address) = .empty,
mode: Mode = .interpreting,

const InnerInterpreter = struct {
    const Error = error{
        InvalidAddress,
        EndOfCode,
    };
    // Executes a word at the given address
    outer: *Interpreter,

    pub fn fetch(self: *InnerInterpreter, cidx: Type.CodeIndex) ?Type.Instruction {
        if (cidx >= self.outer.code_address_list.items.len) {
            return null;
        }
        const instr_addr: Type.Address = self.outer.code_address_list.items[cidx];
        const instr: Type.Instruction = @ptrFromInt(instr_addr);
        return instr;
    }

    pub fn exec(self: *InnerInterpreter, cidx: Type.CodeIndex) Error!void {
        const instr = self.fetch(cidx) orelse return error.InvalidAddress;
        try instr(self.outer);
    }

    pub fn step(self: *InnerInterpreter) Error!void {
        const current_cidx = self.outer.IP / @sizeOf(Type.CodeIndex);
        try self.exec(current_cidx);
        self.outer.IP += @sizeOf(Type.CodeIndex);
    }

    pub fn run(self: *InnerInterpreter) Error!void {
        while (true) {
            self.step() catch |err| {
                if (err == error.EndOfCode) break;
                return err;
            };
        }
    }
};

pub fn init(gpa: Allocator) Interpreter {
    var result = Interpreter{
        .gpa = gpa,
        .inner = undefined,
    };
    result.inner.outer = &result;
    return result;
}

pub fn deinit(self: *Interpreter) void {
    self.dictionary.deinit(self.gpa);
    self.code_address_list.deinit(self.gpa);
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
            } else {
                // Compile the word into the current definition
            }
        },
        .s_int,.u_int => {
            if (self.mode == .interpreting) {
                // Push the literal onto the data stack
            } else {
                // Compile a literal instruction followed by the value
            }
    }
}

pub fn docol(self: *Interpreter) !void {
    self.IP += @sizeOf(Type.CodeIndex);
    // push return address onto the return stack
}

pub fn next(self: *Interpreter) !void {
    const return_address = 0; // pop from return stack
    self.IP = return_address;
}

test "just make sure it compiles"{}