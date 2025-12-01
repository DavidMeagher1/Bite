const std = @import("std");
const Type = @import("type.zig");
const Interpreter = @import("interpreter.zig");
const Dictionary = @import("dictionary.zig");

// notes:
// primitives that modify the IP should do so after calling doexit if they are in interpreting mode or immediate
// this is because the IP will be after the code index of the primitive being executed not in the word that called it
// others that do not modify the IP can just call doexit at the end

// START: functions that are implementation primitive words but are not in the dictionary
pub fn docol(self: *Interpreter) !void {
    try self.return_stack.push(self.gpa, self.IP); // store the address of the next instruction to execute
}

pub fn doexit(self: *Interpreter) !void {
    const return_address = self.return_stack.pop() catch |err| {
        self.inner.halted = true;
        return err;
    };

    if (return_address == Type.Constants.sentinel_return_address) {
        self.inner.halted = true;
        return;
    }

    self.IP = return_address;
}

pub fn execute(interp: *Interpreter) !void {
    const old_ip = interp.IP;
    interp.IP += @sizeOf(Type.CodeIndex); // move past the execute code index
    try docol(interp);
    const addr_bytes = interp.dictionary.data.items[old_ip .. old_ip + @sizeOf(Type.CodeIndex)];
    const addr: Type.CodeIndex = std.mem.bytesToValue(Type.CodeIndex, addr_bytes);
    interp.IP = addr;
}

pub fn does_word(interp: *Interpreter) !void {
    const old_ip = interp.IP;
    interp.IP += @sizeOf(Type.CodeIndex); // move past the does> code index
    try push_data_field_addr(interp); // we do this after incrementing to get past the offset to does>
    try docol(interp);
    const offset_to_does_bytes = interp.dictionary.data.items[old_ip .. old_ip + @sizeOf(Type.CodeIndex)];
    const offset_to_does: Type.CodeIndex = std.mem.bytesToValue(Type.CodeIndex, offset_to_does_bytes);
    const does_addr: Type.CodeIndex = interp.IP + offset_to_does;
    const addr_bytes = interp.dictionary.data.items[does_addr .. does_addr + @sizeOf(Type.CodeIndex)];
    const addr: Type.CodeIndex = std.mem.bytesToValue(Type.CodeIndex, addr_bytes);
    interp.IP = addr;
}

pub fn push_data_field_addr(interp: *Interpreter) !void {
    // we assume the current IP points to a data field address
    const dictionary_addr = @intFromPtr(&interp.dictionary);
    const addr: Type.Cell = dictionary_addr + interp.IP; // IP should be the offset of the data field within the dictionary
    try interp.data_stack.push(interp.gpa, addr); // push the address onto the data stack
}

// END: functions that are implementation primitive words but are not in the dictionary

// START: dictionary definition primitives
pub fn colon(interp: *Interpreter) !void {
    // start a new word definition
    try interp.dictionary.startWord(interp.gpa);
    const token = interp.lexer.next();
    var info: Dictionary.WordInfo = undefined;
    switch (token) {
        .text => |text| {
            info = .{
                .name_len = @truncate(text.len),
                .flags = .{
                    .immediate = false,
                    .smudged = true,
                },
            };
        },
        else => return error.InvalidWordName,
    }
    try interp.dictionary.addWordInfo(interp.gpa, info);
    try interp.dictionary.addName(interp.gpa, token.text);
    try interp.dictionary.addCode(interp.gpa, @intFromPtr(&docol)); // Append docol code
    interp.mode = .compiling;
    try doexit(interp);
}

pub fn semicolon(interp: *Interpreter) !void {
    // finish the current word definition
    try interp.dictionary.addCode(interp.gpa, @intFromPtr(&doexit)); // Append doexit code
    const last_word = interp.dictionary.last_word orelse return error.NoCurrentWord;
    var info = interp.dictionary.getWordInfo(last_word) orelse return error.InvalidAddress;
    info.flags.smudged = false;
    interp.dictionary.setLastFlags(info.flags);
    interp.mode = .interpreting;
    try doexit(interp);
}

// END: dictionary definition primitives

pub fn literal(interp: *Interpreter) !void {
    // in interpreting mode, get the next value and push it onto the stack
    if (interp.mode == .interpreting) {
        const value_bytes = interp.dictionary.data.items[interp.IP .. interp.IP + @sizeOf(Type.Cell)];
        const value: Type.Cell = std.mem.bytesToValue(Type.Cell, value_bytes);
        try interp.data_stack.push(interp.gpa, value);
        interp.IP += @sizeOf(Type.Cell); // move past the literal value
        return;
    }
    // in compiling mode, compile a lit instruction followed by the value
    try interp.dictionary.addCode(interp.gpa, @intFromPtr(&literal)); // compile lit instruction
    // get the next value
    const value = interp.lexer.next();
    switch (value) {
        .s_int => |v_int| {
            try interp.dictionary.addCode(interp.gpa, @bitCast(v_int));
        },
        .u_int => |v_int| {
            try interp.dictionary.addCode(interp.gpa, @bitCast(v_int));
        },
        else => return error.InvalidLiteral,
    }
    interp.IP += @sizeOf(Type.Cell); // move past the literal value
    try doexit(interp);
}

// START: meta word primitives
pub fn create(interp: *Interpreter) !void {
    // create a new word definition
    try interp.dictionary.startWord(interp.gpa);
    const token = interp.lexer.next();
    var info: Dictionary.WordInfo = undefined;
    switch (token) {
        .text => |text| {
            if (text.len >= Type.Constants.max_word_name_length) {
                return error.InvalidWordName;
            }
            info = .{
                .name_len = @truncate(text.len),
                .flags = .{ .immediate = false, .smudged = true },
            };
        },
        else => return error.InvalidWordName,
    }
    try interp.dictionary.addWordInfo(interp.gpa, info);
    try interp.dictionary.addName(interp.gpa, token.text[0..@truncate(token.text.len)]);
    try interp.dictionary.addCode(interp.gpa, @intFromPtr(&push_data_field_addr)); // Append push_data_field_addr code
    try interp.dictionary.addCode(interp.gpa, interp.dictionary.here()); // Append doexit code
}

pub fn does(interp: *Interpreter) !void {
    // set up a DOES> for the last created word
    const here = interp.dictionary.here();
    const last_word = interp.dictionary.last_word orelse return error.NoCurrentWord;
    var info = interp.dictionary.getWordInfo(last_word) orelse return error.InvalidAddress;
    if (!info.flags.smudged) {
        return error.InvalidDoes;
    }
    // compile the DOES> code point
    const data_offset = last_word + info.getDataOffset();
    const create_start_bytes = interp.dictionary.data.items[data_offset .. data_offset + @sizeOf(Type.CodeIndex)];
    const offset_to_does: Type.CodeIndex = here - std.mem.bytesToValue(Type.CodeIndex, create_start_bytes);
    try interp.dictionary.setLastCode(@intFromPtr(&does_word));
    try interp.dictionary.setLastData(0, offset_to_does);
    try interp.dictionary.addCode(interp.gpa, @intFromPtr(&execute)); // Append doexit code
    try interp.dictionary.addData(interp.gpa, interp.IP); // append doexit after the DOES> code
    try interp.dictionary.addData(interp.gpa, @intFromPtr(&doexit)); // Append doexit code
    info.flags.smudged = false;
    interp.dictionary.setLastFlags(info.flags);
    try doexit(interp); // so we dont execute the DOES> code now
}

pub fn immediate(interp: *Interpreter) !void {
    try doexit(interp);
    const last_word = interp.dictionary.last_word orelse return error.NoCurrentWord;
    var info = interp.dictionary.getWordInfo(last_word) orelse return error.InvalidAddress;
    info.flags.immediate = true;
    interp.dictionary.setLastFlags(info.flags);
}

pub fn comma(interp: *Interpreter) !void {
    const value = try interp.data_stack.pop();
    std.debug.print("Comma: {d}\n", .{value});
    try interp.dictionary.addData(interp.gpa, value);
}

pub fn exit(interp: *Interpreter) !void {
    try doexit(interp);
}

// START: arithmetic primitive words
pub fn add(interp: *Interpreter) !void {
    const b: Type.Cell = try interp.data_stack.pop();
    const a: Type.Cell = try interp.data_stack.pop();
    try interp.data_stack.push(interp.gpa, a + b);
    //try doexit(interp);
}

pub fn sub(interp: *Interpreter) !void {
    const b: Type.Cell = try interp.data_stack.pop();
    const a: Type.Cell = try interp.data_stack.pop();
    try interp.data_stack.push(interp.gpa, a - b);
}

pub fn mul(interp: *Interpreter) !void {
    const b: Type.Cell = try interp.data_stack.pop();
    const a: Type.Cell = try interp.data_stack.pop();
    try interp.data_stack.push(interp.gpa, a * b);
}

pub fn div(interp: *Interpreter) !void {
    const b: Type.Cell = try interp.data_stack.pop();
    const a: Type.Cell = try interp.data_stack.pop();
    if (b == 0) {
        return error.DivideByZero;
    }
    try interp.data_stack.push(interp.gpa, a / b);
}

// END: arithmetic primitive words

// START: Stack manipulation primitive words

pub fn drop(interp: *Interpreter) !void {
    _ = try interp.data_stack.pop();
}

pub fn dup(interp: *Interpreter) !void {
    try interp.data_stack.dup(interp.gpa);
}

pub fn swap(interp: *Interpreter) !void {
    try interp.data_stack.swap();
}

pub fn over(interp: *Interpreter) !void {
    try interp.data_stack.over(interp.gpa);
}

pub fn rot(interp: *Interpreter) !void {
    try interp.data_stack.rot();
}

pub fn tuck(interp: *Interpreter) !void {
    try interp.data_stack.tuck(interp.gpa);
}

pub fn nip(interp: *Interpreter) !void {
    try interp.data_stack.nip();
}

// END: Stack manipulation primitive words

// START: memory primitives

pub fn at(interp: *Interpreter) !void {
    std.debug.print("Executing @ primitive\n", .{});
    const addr: Type.Cell = try interp.data_stack.pop();
    const ptr: *const Type.Cell = @ptrFromInt(addr);
    const value: Type.Cell = ptr.*;
    try interp.data_stack.push(interp.gpa, value);
}

pub fn debug_print(interp: *Interpreter) !void {
    const value: Type.Cell = try interp.data_stack.pop();
    std.debug.print("Top of stack: {d}\n", .{value});
}

pub fn register_defaults(interp: *Interpreter) !void {
    // word definition primitives
    try interp.register_primitive(":", colon, true);
    try interp.register_primitive(";", semicolon, true);
    // arithmetic primitives
    try interp.register_primitive("+", add, false);
    try interp.register_primitive("-", sub, false);
    try interp.register_primitive("*", mul, false);
    try interp.register_primitive("/", div, false);
    // stack manipulation primitives
    try interp.register_primitive("LITERAL", literal, true);
    try interp.register_primitive("DROP", drop, false);
    try interp.register_primitive("DUP", dup, false);
    try interp.register_primitive("SWAP", swap, false);
    try interp.register_primitive("OVER", over, false);
    try interp.register_primitive("ROT", rot, false);
    try interp.register_primitive("TUCK", tuck, false);
    try interp.register_primitive("NIP", nip, false);
    // meta-primitives
    try interp.register_primitive("CREATE", create, false);
    try interp.register_primitive("DOES>", does, false);
    try interp.register_primitive("IMMEDIATE", immediate, false);
    try interp.register_primitive(",", comma, false);
    // memory primitives
    try interp.register_primitive("@", at, false);
    // others TODO: categorize
    try interp.register_primitive("EXIT", exit, false);
    try interp.register_primitive(".", debug_print, false);
}
