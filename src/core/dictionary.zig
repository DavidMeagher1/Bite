const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Type = @import("type.zig");
const Dictionary = @This();

pub const WordFlags = packed struct(u3) {
    immediate: bool = false,
    smudged: bool = false,
    hidden: bool = false,
};

pub const WordInfo = packed struct(u8) {
    flags: WordFlags = .{},
    name_len: u5 = 0,

    pub fn getCodeOffset(self: WordInfo) usize {
        return Dictionary.NAME_OFFSET + self.name_len;
    }

    pub fn getDataOffset(self: WordInfo) usize {
        return self.getCodeOffset() + Dictionary.CODE_SIZE;
    }
};

test "WordInfo size is 1 byte" {
    try std.testing.expectEqual(@sizeOf(WordInfo), 1);
}

pub const Word = struct {
    link: Type.Address,
    info: WordInfo,
    name: []const u8,
    code_index: Type.CodeIndex,
    data: ?[]Type.CodeIndex,
};

data: ArrayListUnmanaged(u8) = .empty,
second_last_word: ?Type.Address = null,
last_word: ?Type.Address = null,
here: Type.Address = 0,

pub const LINK_OFFSET: usize = 0;
pub const INFO_OFFSET: usize = LINK_OFFSET + @sizeOf(Type.Address);
pub const NAME_OFFSET: usize = INFO_OFFSET + @sizeOf(WordInfo);
pub const CODE_SIZE: usize = @sizeOf(Type.CodeIndex);

pub fn deinit(self: *Dictionary, gpa: Allocator) void {
    self.data.deinit(gpa);
    self.last_word = null;
    self.here = 0;
}

pub fn startWord(self: *Dictionary, gpa: Allocator) !void {
    if (self.last_word) |last| {
        const written = try self.addLink(gpa, last);
        self.second_last_word = self.last_word;
        self.last_word = self.here;
        self.here += written;
    } else {
        const written = try self.addLink(gpa, 0);
        self.last_word = self.here;
        self.here += written;
    }
}

pub fn addLink(self: *Dictionary, gpa: Allocator, link: Type.Address) !usize {
    const link_bytes = mem.asBytes(&link);
    try self.data.appendSlice(gpa, link_bytes);
    return @sizeOf(Type.Address);
}

pub fn getLink(self: *Dictionary, address: Type.Address) ?*Type.Address {
    if (address + @sizeOf(Type.Address) > self.data.items.len) {
        return null;
    }
    const link_bytes = self.data.items[address .. address + @sizeOf(Type.Address)];
    const link: *Type.Address = mem.bytesAsValue(Type.Address, link_bytes);
    return link;
}

pub fn addWordInfo(self: *Dictionary, gpa: Allocator, info: WordInfo) !usize {
    const info_bytes = mem.asBytes(&info);
    try self.data.appendSlice(gpa, info_bytes);
    return @sizeOf(WordInfo);
}

pub fn getWordInfo(self: *Dictionary, address: Type.Address) ?*WordInfo {
    if (address + @sizeOf(WordInfo) > self.data.items.len) {
        return null;
    }
    const info_bytes = self.data.items[address .. address + @sizeOf(WordInfo)];
    const info: *WordInfo = mem.bytesAsValue(WordInfo, info_bytes);
    return info;
}

pub fn addName(self: *Dictionary, gpa: Allocator, name: []const u8) !usize {
    try self.data.appendSlice(gpa, name);
    return name.len;
}

pub fn addCode(self: *Dictionary, gpa: Allocator, code_index: Type.CodeIndex) !usize {
    const code_bytes = mem.asBytes(&code_index);
    try self.data.appendSlice(gpa, code_bytes);
    return @sizeOf(Type.CodeIndex);
}

pub fn getCode(self: *Dictionary, address: Type.Address) ?Type.CodeIndex {
    if (address + @sizeOf(Type.CodeIndex) > self.data.items.len) {
        return null;
    }
    const code_bytes = self.data.items[address .. address + @sizeOf(Type.CodeIndex)];
    const code_index: *Type.CodeIndex = mem.bytesAsValue(Type.CodeIndex, code_bytes);
    return code_index.*;
}

pub fn addData(self: *Dictionary, gpa: Allocator, data: Type.CodeIndex) !usize {
    const data_bytes = mem.asBytes(&data);
    try self.data.appendSlice(gpa, data_bytes);
    return @sizeOf(Type.CodeIndex);
}

pub fn findWord(self: *Dictionary, name: []const u8) ?Type.Address {
    var current = self.last_word;
    while (current) |addr| {
        const info_bytes = self.data.items[addr + INFO_OFFSET .. addr + INFO_OFFSET + @sizeOf(WordInfo)];
        const info = mem.bytesToValue(WordInfo, info_bytes);
        if (info.name_len != name.len) {
            const link_ptr = self.getLink(addr) orelse return null;
            current = link_ptr.*;
            continue;
        }
        const name_start = addr + NAME_OFFSET;
        const name_end = name_start + info.name_len;
        const word_name = self.data.items[name_start..name_end];
        if (mem.eql(u8, word_name, name)) {
            return addr;
        }
        const link_ptr = self.getLink(addr) orelse return null;
        current = link_ptr.*;
    }
    return null;
}

pub fn getWord(self: *Dictionary, name: []const u8) ?Word {
    var current = self.last_word;
    var last_addr: ?Type.Address = null;
    while (current) |addr| {
        last_addr = current;
        const info_bytes = self.data.items[addr + INFO_OFFSET .. addr + INFO_OFFSET + @sizeOf(WordInfo)];
        const info: WordInfo = mem.bytesToValue(WordInfo, info_bytes);
        if (info.name_len != name.len) {
            const link_ptr = self.getLink(addr) orelse return null;
            current = link_ptr.*;
            continue;
        }
        const name_start = addr + NAME_OFFSET;
        const name_end = name_start + info.name_len;
        const word_name = self.data.items[name_start..name_end];
        if (mem.eql(u8, word_name, name)) {
            const code_index_bytes = self.data.items[name_end .. name_end + CODE_SIZE];
            const code_index: Type.CodeIndex = mem.bytesToValue(Type.CodeIndex, code_index_bytes);
            const data_start = name_end + CODE_SIZE;
            var data_end: Type.Address = 0;
            if (addr == self.last_word) {
                data_end = self.data.items.len;
            } else {
                data_end = last_addr orelse unreachable;
            }
            const data = self.data.items[data_start..data_end];
            const link_ptr = self.getLink(addr) orelse 0;
            return Word{
                .link = link_ptr.*,
                .info = info,
                .name = word_name,
                .code_index = code_index,
                .data = data,
            };
        }
        const link_ptr = self.getLink(addr) orelse return null;
        current = link_ptr.*;
    }
    return null;
}

pub fn setLastFlags(self: *Dictionary, flags: WordFlags) void {
    const address = self.last_word orelse return;
    const info = self.getWordInfo(address) orelse return;
    info.flags = flags;
}
