//! The dictionary is a byte array that contains the information about defined
//! words

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Dictionary = @This();
const ByteList = ArrayListUnmanaged(u8);

/// offset of the info byte from the start of a word entry
pub const INFO_OFFSET: usize = @sizeOf(Index);
pub const NAME_OFFSET: usize = INFO_OFFSET + @sizeOf(Info);

const Error = error{
    NameTooLong,
    WordNotFound,
};

/// A packed struct to hold the info byte for a word
/// easier to work with than bit manipulation
pub const Info = packed struct(u8) {
    smuged: bool = false,
    immediate: bool = false,
    reserved: bool = false,
    name_length: u5,

    pub fn fromByte(byte: u8) Info {
        return @bitCast(byte);
    }

    pub fn toByte(self: Info) u8 {
        return @bitCast(self);
    }

    pub fn nameEndOffset(self: Info) usize {
        return NAME_OFFSET + self.name_length;
    }
};
/// Index into the dictionary byte array
pub const Index = enum(u32) {
    const Error = error{
        MisalignedIndex,
        IndexOutOfBounds,
    };

    zero,
    _,

    pub fn toInt(self: Index) usize {
        switch (self) {
            .zero => return 0,
            else => return @as(usize, @intFromEnum(self)),
        }
    }

    pub fn fromInt(i: usize) Index {
        if (i == 0) return .zero;
        return @enumFromInt(@as(u32, @truncate(i)));
    }

    pub fn within_bounds(self: Index, upper: usize) bool {
        return self.toInt() < upper;
    }

    pub fn ensure_within_bounds(self: Index, upper: usize) Index.Error!void {
        if (!self.within_bounds(upper)) {
            return error.IndexOutOfBounds;
        }
    }

    pub fn add(self: Index, offset: usize) Index {
        return Index.fromInt(self.toInt() + offset);
    }

    pub fn sub(self: Index, offset: usize) Index {
        return Index.fromInt(self.toInt() - offset);
    }

    pub fn is_aligned(self: Index, alignment: usize) bool {
        return (self.toInt() % alignment) == 0;
    }

    pub fn ensure_aligned(self: Index, alignment: usize) Index.Error!void {
        if (!self.is_aligned(alignment)) {
            return error.MisalignedIndex;
        }
    }

    pub fn forward_aligned(self: Index, alignment: usize) Index {
        const remainder = self.toInt() % alignment;
        if (remainder == 0) {
            return self;
        } else {
            const padding = alignment - remainder;
            return self.add(padding);
        }
    }

    pub fn backward_aligned(self: Index, alignment: usize) Index {
        const remainder = self.toInt() % alignment;
        if (remainder == 0) {
            return self;
        } else {
            return self.sub(remainder);
        }
    }
};

pub const ExecutionToken = usize;

data: ByteList = .empty,
last: Index = .zero,
head: Index = .zero,
_internal_mark: Index = .zero,
_internal_last: Index = .zero,

pub fn deinit(dict: *Dictionary, gpa: Allocator) void {
    dict.data.deinit(gpa);
}

fn addAligned(dict: *Dictionary, gpa: Allocator, bytes: []const u8, alignment: usize) !void {
    const padding = (alignment - (dict.data.items.len % alignment)) % alignment;
    if (padding != 0) {
        try dict.data.appendNTimes(gpa, 0, padding);
        dict.head = dict.head.add(@truncate(padding));
    }
    try dict.data.appendSlice(gpa, bytes);
    dict.head = dict.head.add(@truncate(bytes.len));
}

pub fn addLink(dict: *Dictionary, gpa: Allocator, link: Index) !void {
    const bytes: []const u8 = mem.asBytes(&link);
    try dict.addAligned(gpa, bytes, @alignOf(usize));
}

pub fn getLink(dict: *const Dictionary, index: Index) Index.Error!Index {
    try index.ensure_aligned(@alignOf(usize));
    try index.ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    const linkBytes = dict.data.items[i .. i + @sizeOf(Index)];
    const link: *const Index = @alignCast(mem.bytesAsValue(Index, linkBytes));
    return link.*;
}

pub fn setLink(dict: *Dictionary, index: Index, link: Index) Index.Error!void {
    try index.ensure_aligned(@alignOf(usize));
    try index.ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    const linkBytes: []u8 = mem.asBytes(&link);
    @memcpy(dict.data.items[i .. i + @sizeOf(Index)], linkBytes);
}

pub fn addInfo(dict: *Dictionary, gpa: Allocator, info: Info) !void {
    const byte: u8 = info.toByte();
    try dict.data.append(gpa, byte);
    dict.head = dict.head.add(@sizeOf(u8));
}

pub fn getInfo(dict: *const Dictionary, index: Index) Index.Error!Info {
    try index.ensure_within_bounds(dict.data.items.len);
    const byte = dict.data.items[index.toInt()];
    return Info.fromByte(byte);
}

pub fn setInfo(dict: *Dictionary, index: Index, info: Info) Index.Error!void {
    try index.ensure_within_bounds(dict.data.items.len);
    const byte: u8 = info.toByte();
    dict.data.items[index.toInt()] = byte;
}

pub fn addName(dict: *Dictionary, gpa: Allocator, name: []const u8) !void {
    // name isnt aligned to any boundary, so just append
    if (name.len > 31) { // magic number from Info.name_length u5 TODO improve
        return error.NameTooLong;
    }
    try dict.data.appendSlice(gpa, name);
    dict.head = dict.head.add(@truncate(name.len));
}

pub fn getName(dict: *const Dictionary, index: Index, length: usize) Index.Error![]const u8 {
    try index.add(length - 1).ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    return dict.data.items[i .. i + length];
}

pub fn addExecutionToken(dict: *Dictionary, gpa: Allocator, token: usize) !void {
    const bytes: []const u8 = mem.asBytes(&token);
    try dict.addAligned(gpa, bytes, @alignOf(usize));
}

pub fn getExecutionToken(dict: *const Dictionary, index: Index) Index.Error!ExecutionToken {
    try index.ensure_aligned(@alignOf(usize));
    try index.ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    const tokenBytes = dict.data.items[i .. i + @sizeOf(ExecutionToken)];
    const token: *const ExecutionToken = @alignCast(mem.bytesAsValue(ExecutionToken, tokenBytes));
    return token.*;
}

pub fn setExecutionToken(dict: *Dictionary, index: Index, token: ExecutionToken) Index.Error!void {
    try index.ensure_aligned(@alignOf(usize));
    try index.ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    const tokenBytes: []const u8 = @alignCast(mem.asBytes(&token));
    @memcpy(dict.data.items[i .. i + @sizeOf(ExecutionToken)], tokenBytes);
}

pub fn addParameter(dict: *Dictionary, gpa: Allocator, T: type, param: T) !void {
    const bytes: []const u8 = mem.asBytes(&param);
    try dict.data.appendSlice(gpa, bytes);
    // update head so subsequent indices use the correct offset
    dict.head = dict.head.add(@truncate(bytes.len));
}

pub fn getParameter(dict: *const Dictionary, index: Index, T: type) Index.Error!T {
    const param_size = @sizeOf(T);
    try index.ensure_within_bounds(dict.data.items.len);
    try index.add(param_size - 1).ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    const paramBytes = dict.data.items[i .. i + param_size];
    const param_ptr: *const T = @alignCast(mem.bytesAsValue(T, paramBytes));
    return param_ptr.*;
}

pub fn setParameter(dict: *Dictionary, index: Index, T: type, param: T) Index.Error!void {
    const param_size = @sizeOf(T);
    try index.ensure_within_bounds(dict.data.items.len);
    try index.add(param_size - 1).ensure_within_bounds(dict.data.items.len);
    const i = index.toInt();
    const paramBytes: []u8 = mem.asBytes(&param);
    @memcpy(dict.data.items[i .. i + param_size], paramBytes);
}

pub fn createWord(dict: *Dictionary, gpa: Allocator) !Index {
    const last_word_index = dict.last;
    dict.last = dict.head;
    try dict.addLink(gpa, last_word_index);
    return dict.last;
}

pub fn getWord(dict: *const Dictionary, name: []const u8) !Index {
    var current_index = dict.last;
    while (true) {
        const info_index = current_index.add(INFO_OFFSET);
        const info = try dict.getInfo(info_index);
        if (!info.smuged) {
            const name_index = current_index.add(NAME_OFFSET);
            const word_name = try dict.getName(name_index, info.name_length);
            if (mem.eql(u8, word_name, name)) {
                return current_index;
            }
        }
        const last_index = current_index;
        current_index = try dict.getLink(current_index);
        if (current_index == last_index) {
            // this means that our link pointed to itself, so we've reached the end
            return error.WordNotFound;
        }
    }
}

pub fn findWord(dict: *const Dictionary, name: []const u8) !?Index {
    return dict.getWord(name) catch |err| {
        if (err == error.WordNotFound) {
            return null;
        } else {
            return err;
        }
    };
}

pub fn mark(dict: *Dictionary) void {
    dict._internal_mark = dict.head;
    dict._internal_last = dict.last;
}

pub fn resetToMark(dict: *Dictionary, gpa: Allocator) !void {
    dict.head = dict._internal_mark;
    dict.last = dict._internal_last;
    try dict.data.resize(gpa, dict.head.toInt());
}

test "addLink getLink" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    try dict.addLink(allocator, Index.fromInt(0x12345678));
    try dict.addLink(allocator, Index.fromInt(0x9ABCDEF0));
    const link1 = try dict.getLink(.zero);
    const link2 = try dict.getLink(Index.fromInt(@sizeOf(usize)));
    try std.testing.expect(link1.toInt() == 0x12345678);
    try std.testing.expect(link2.toInt() == 0x9ABCDEF0);
}

test "addInfo and getInfo" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    const info1 = Info{
        .smuged = true,
        .immediate = false,
        .reserved = true,
        .name_length = 15,
    };
    const info2 = Info{
        .smuged = false,
        .immediate = true,
        .reserved = false,
        .name_length = 7,
    };

    try dict.addInfo(allocator, info1);
    try dict.addInfo(allocator, info2);

    const retrieved1 = try dict.getInfo(.zero);
    const retrieved2 = try dict.getInfo(Index.fromInt(1));
    try std.testing.expect(retrieved1 == info1);
    try std.testing.expect(retrieved2 == info2);
}

test "addName and getName" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    const name1 = "Hello";
    const name2 = "World!";

    try dict.addName(allocator, name1);
    try dict.addName(allocator, name2);

    const retrieved1 = try dict.getName(.zero, name1.len);
    const retrieved2 = try dict.getName(Index.fromInt(name1.len), name2.len);

    try std.testing.expect(mem.eql(u8, retrieved1, name1));
    try std.testing.expect(mem.eql(u8, retrieved2, name2));
}

test "addExecutionToken and getExecutionToken" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    try dict.addExecutionToken(allocator, 0xDEADBEEF);
    try dict.addExecutionToken(allocator, 0xFEEDC0DE);

    const token1 = try dict.getExecutionToken(.zero);
    const token2 = try dict.getExecutionToken(Index.fromInt(@sizeOf(usize)));

    try std.testing.expect(token1 == 0xDEADBEEF);
    try std.testing.expect(token2 == 0xFEEDC0DE);
}

test "add test word" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    const word_start = try dict.createWord(allocator);

    const info = Info{
        .smuged = false,
        .immediate = true,
        .reserved = false,
        .name_length = 4,
    };
    try dict.addInfo(allocator, info);
    try dict.addName(allocator, "Test");
    try dict.addExecutionToken(allocator, 0xCAFEBABE);

    const retrieved_info = try dict.getInfo(word_start.add(INFO_OFFSET));
    const retrieved_name = try dict.getName(word_start.add(NAME_OFFSET), info.name_length);
    const execution_offset = word_start.add(info.nameEndOffset()).forward_aligned(@alignOf(usize));
    const retrieved_token = try dict.getExecutionToken(execution_offset);

    try std.testing.expect(retrieved_info == info);
    try std.testing.expect(mem.eql(u8, retrieved_name, "Test"));
    try std.testing.expect(retrieved_token == 0xCAFEBABE);
}

test "multiple word head and last test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    const word1_start = try dict.createWord(allocator);
    try dict.addInfo(allocator, Info{ .smuged = false, .immediate = false, .reserved = false, .name_length = 3 });
    try dict.addName(allocator, "One");
    try dict.addExecutionToken(allocator, 0x11111111);

    const word2_start = try dict.createWord(allocator);
    try dict.addInfo(allocator, Info{ .smuged = true, .immediate = true, .reserved = false, .name_length = 3 });
    try dict.addName(allocator, "Two");
    try dict.addExecutionToken(allocator, 0x22222222);

    const word3_start = try dict.createWord(allocator);
    try dict.addInfo(allocator, Info{ .smuged = false, .immediate = true, .reserved = true, .name_length = 5 });
    try dict.addName(allocator, "Three");
    try dict.addExecutionToken(allocator, 0x33333333);

    const retrieved_token1 = try dict.getExecutionToken(word1_start.add(NAME_OFFSET + 3).forward_aligned(@alignOf(usize)));
    const retrieved_token2 = try dict.getExecutionToken(word2_start.add(NAME_OFFSET + 3).forward_aligned(@alignOf(usize)));
    const retrieved_token3 = try dict.getExecutionToken(word3_start.add(NAME_OFFSET + 5).forward_aligned(@alignOf(usize)));

    try std.testing.expect(retrieved_token1 == 0x11111111);
    try std.testing.expect(retrieved_token2 == 0x22222222);
    try std.testing.expect(retrieved_token3 == 0x33333333);

    const retrived_link3 = try dict.getLink(word3_start);
    const retrived_link2 = try dict.getLink(word2_start);
    const retrived_link1 = try dict.getLink(word1_start);
    try std.testing.expect(retrived_link3 == word2_start);
    try std.testing.expect(retrived_link2 == word1_start);
    try std.testing.expect(retrived_link1 == .zero);
    try std.testing.expect(dict.last == word3_start);
    try std.testing.expect(dict.head.toInt() == dict.data.items.len);
}

test "Index alignment checks" {
    const alignment = 4;
    const aligned_index = Index.fromInt(8);
    const misaligned_index = Index.fromInt(10);
    try std.testing.expect(aligned_index.is_aligned(alignment));
    try std.testing.expect(!misaligned_index.is_aligned(alignment));
    try std.testing.expect(misaligned_index.backward_aligned(alignment) == aligned_index);
    try std.testing.expect(Index.fromInt(6).forward_aligned(alignment) == aligned_index);
}

test "findWord" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dict = Dictionary{};
    defer dict.deinit(allocator);

    const word1_start = try dict.createWord(allocator);
    try dict.addInfo(allocator, Info{ .smuged = false, .immediate = false, .reserved = false, .name_length = 3 });
    try dict.addName(allocator, "One");
    try dict.addExecutionToken(allocator, 0x11111111);

    const word2_start = try dict.createWord(allocator);
    try dict.addInfo(allocator, Info{ .smuged = false, .immediate = true, .reserved = false, .name_length = 3 });
    try dict.addName(allocator, "Two");
    try dict.addExecutionToken(allocator, 0x22222222);

    const found_word1 = try dict.findWord("One") orelse unreachable;
    const found_word2 = try dict.findWord("Two") orelse unreachable;
    const not_found = try dict.findWord("Three");

    try std.testing.expect(found_word1 == word1_start);
    try std.testing.expect(found_word2 == word2_start);
    try std.testing.expect(not_found == null);
}

test "info bitcast" {
    const info = Info{
        .smuged = true,
        .immediate = false,
        .reserved = true,
        .name_length = 21,
    };
    const byte = info.toByte();
    const reconstructed_info = Info.fromByte(byte);
    try std.testing.expect(reconstructed_info == info);
}
