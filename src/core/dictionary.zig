const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Type = @import("type.zig");
const Dictionary = @This();

pub const Error = error{
    InvalidAddress,
};

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
    link: Type.WordIndex,
    info: WordInfo,
    name: []const u8,
    code_index: Type.CodeIndex,
    data: ?[]Type.CodeIndex,
};

data: ArrayListUnmanaged(u8) = .empty,
last_word: ?Type.WordIndex = null,

pub const LINK_OFFSET: usize = 0;
pub const INFO_OFFSET: usize = LINK_OFFSET + @sizeOf(Type.WordIndex);
pub const NAME_OFFSET: usize = INFO_OFFSET + @sizeOf(WordInfo);
pub const CODE_SIZE: usize = @sizeOf(Type.CodeIndex);

pub fn deinit(self: *Dictionary, gpa: Allocator) void {
    self.data.deinit(gpa);
    self.last_word = null;
}

pub fn here(self: *Dictionary) Type.WordIndex {
    return self.data.items.len;
}

fn addAligned(self: *Dictionary, gpa: Allocator, alignment: usize, data: []const u8) !void {
    const data_len = data.len;
    const aligned = std.mem.alignForward(usize, data_len, alignment);
    try self.data.appendSlice(gpa, data);
    if (aligned > data_len) {
        const padding = aligned - data_len;
        try self.data.appendNTimes(gpa, 0, padding);
    }
}

pub fn startWord(self: *Dictionary, gpa: Allocator) !void {
    const link = self.last_word orelse 0;
    self.last_word = self.here();
    try self.addLink(gpa, link);
}

pub fn addLink(self: *Dictionary, gpa: Allocator, link: Type.WordIndex) !void {
    const link_bytes = mem.toBytes(link);
    try self.data.appendSlice(gpa, &link_bytes);
}

pub fn getLink(self: *Dictionary, widx: Type.WordIndex) ?Type.WordIndex {
    if (widx + @sizeOf(Type.WordIndex) > self.data.items.len) {
        return null;
    }
    const link_bytes = self.data.items[widx .. widx + @sizeOf(Type.WordIndex)];
    const link: Type.WordIndex = mem.bytesToValue(Type.WordIndex, link_bytes);
    return link;
}

pub fn addWordInfo(self: *Dictionary, gpa: Allocator, info: WordInfo) !void {
    const info_bytes = mem.toBytes(info);
    try self.data.appendSlice(gpa, &info_bytes);
}

pub fn getWordInfo(self: *Dictionary, widx: Type.WordIndex) ?WordInfo {
    if ((widx + NAME_OFFSET) > self.data.items.len) {
        return null;
    }
    const info_bytes = self.data.items[widx + INFO_OFFSET .. widx + NAME_OFFSET];
    const info: WordInfo = mem.bytesToValue(WordInfo, info_bytes);
    return info;
}

pub fn addName(self: *Dictionary, gpa: Allocator, name: []const u8) !void {
    try self.data.appendSlice(gpa, name);
}

pub fn addCode(self: *Dictionary, gpa: Allocator, address: Type.Address) !void {
    const addr_bytes = mem.toBytes(address);
    try self.data.appendSlice(gpa, &addr_bytes);
}

pub fn setLastCode(self: *Dictionary, address: Type.Address) !void {
    if (self.last_word == null) {
        return Error.InvalidAddress;
    }
    const lwidx = self.last_word.?;
    const winfo = self.getWordInfo(lwidx) orelse return Error.InvalidAddress;
    const code_offset = winfo.getCodeOffset();
    if (lwidx + code_offset + @sizeOf(Type.Address) > self.data.items.len) {
        return Error.InvalidAddress;
    }
    const addr_bytes = mem.toBytes(address);
    @memcpy(self.data.items[lwidx + code_offset .. lwidx + code_offset + @sizeOf(Type.Address)], &addr_bytes);
    return;
}

pub fn getCode(self: *Dictionary, widx: Type.WordIndex) ?Type.CodeIndex {
    const winfo = self.getWordInfo(widx) orelse return null;
    const code_offset = winfo.getCodeOffset();
    if (widx + code_offset + @sizeOf(Type.CodeIndex) > self.data.items.len) {
        return null;
    }
    const code_index: Type.CodeIndex = mem.bytesToValue(Type.CodeIndex, self.data.items[widx + code_offset .. widx + code_offset + @sizeOf(Type.CodeIndex)]);
    return code_index;
}

pub fn addData(self: *Dictionary, gpa: Allocator, data: Type.Address) !void {
    const data_bytes = mem.toBytes(data);
    try self.data.appendSlice(gpa, &data_bytes);
}

pub fn setLastData(self: *Dictionary, offset: usize, data: Type.Address) !void {
    if (self.last_word == null) {
        return Error.InvalidAddress;
    }
    const lwidx = self.last_word.?;
    const winfo = self.getWordInfo(lwidx) orelse return Error.InvalidAddress;
    const data_offset = winfo.getDataOffset() + (offset * @sizeOf(Type.Address));
    if (lwidx + data_offset + @sizeOf(Type.Address) > self.data.items.len) {
        return Error.InvalidAddress;
    }
    const data_bytes = mem.toBytes(data);
    @memcpy(self.data.items[lwidx + data_offset .. lwidx + data_offset + @sizeOf(Type.Address)], &data_bytes);
    return;
}

pub fn findWordBase(self: *Dictionary, name: []const u8, include_hidden: bool) ?Type.WordIndex {
    var current = self.last_word;
    while (current) |addr| {
        const info = self.getWordInfo(addr) orelse break;
        if (info.name_len != name.len or info.flags.smudged or (!include_hidden and info.flags.hidden)) {
            const link = self.getLink(addr) orelse break;
            if (current == link) {
                break;
            }
            current = link;
            continue;
        }
        const name_start = addr + NAME_OFFSET;
        const name_end = name_start + info.name_len;
        const word_name = self.data.items[name_start..name_end];
        if (mem.eql(u8, word_name, name)) {
            return addr;
        }
        const link = self.getLink(addr) orelse return null;
        if (current == link) {
            break;
        }
        current = link;
    }
    return null;
}

pub inline fn findWord(self: *Dictionary, name: []const u8) ?Type.WordIndex {
    return self.findWordBase(name, false);
}

pub inline fn findHiddenWord(self: *Dictionary, name: []const u8) ?Type.WordIndex {
    return self.findWordBase(name, true);
}

pub fn setLastFlags(self: *Dictionary, flags: WordFlags) void {
    if (self.last_word == null) {
        return;
    }
    const widx = self.last_word.?;
    const info_offset = widx + INFO_OFFSET;
    const info_bytes = self.data.items[info_offset .. info_offset + @sizeOf(WordInfo)];
    var info: WordInfo = mem.bytesToValue(WordInfo, info_bytes);
    info.flags = flags;
    const new_info_bytes = mem.toBytes(info);
    @memcpy(self.data.items[info_offset .. info_offset + @sizeOf(WordInfo)], &new_info_bytes);
}
