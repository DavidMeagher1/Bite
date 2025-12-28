const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Dictionary = @import("dictionary.zig").Dictionary;
const Tokenizer = @import("tokenizer.zig");
const primitives = @import("primitives.zig");
const PrimitiveFunction = primitives.PrimitiveFunction;
const Stack = @import("stack.zig").Stack;

const Interp = @This();

const Mode = enum {
    Interpret,
    Compile,
};

reader: std.io.Reader,
dict: *Dictionary,
tokenizer: Tokenizer.Tokenizer,
mode: Mode = .Interpret,
data_stack: Stack(usize),
return_stack: Stack(usize),

pub fn next(self: *Interp) !?void {
    const token = self.tokenizer.next();
    if (token == null) {
        return null;
    }
    switch (token.?) {
        .symbol => |sym| {
            const word_index = try self.dict.getWord(sym);
            const info = try self.dict.getInfo(word_index.add(Dictionary.INFO_OFFSET));
            switch (self.mode) {
                .Interpret => {
                    const exec_token = try self.dict.getExecutionToken(word_index.add(info.nameEndOffset()).forward_aligned(@alignOf(usize)));
                    const fn_ptr: PrimitiveFunction = @ptrFromInt(exec_token);
                    try fn_ptr(self);
                },
                .Compile => {
                    if (info.immediate) {
                        const exec_token = try self.dict.getExecutionToken(word_index.add(Dictionary.INFO_OFFSET).forward_aligned(@alignOf(usize)));
                        const fn_ptr: PrimitiveFunction = @ptrFromInt(exec_token);
                        try fn_ptr(self);
                    } else {
                        // In compile mode, we would compile the word into the dictionary
                        // (compilation implementation not shown here)
                    }
                },
            }
        },
        .number => |num| {
            _ = num; // use num to avoid unused variable warning
            switch (self.mode) {
                .Interpret => {
                    // In interpret mode, we might want to push the number onto a stack
                    // (stack implementation not shown here)
                },
                .Compile => {
                    // In compile mode, we might want to compile the number into the dictionary
                    // (compilation implementation not shown here)
                },
            }
        },
    }
}
