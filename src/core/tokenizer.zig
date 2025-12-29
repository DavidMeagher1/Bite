const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const fmt = std.fmt;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const io = std.io;

const Tokenizer = @This();

// should i automatically parse integers?

buffer: ArrayListUnmanaged(u8) = .empty,
seek: usize = 0,
end: usize = 0,
_needs_input: bool = false,

const Result = union(enum) {
    symbol: []const u8,
    number: usize,
};

const State = enum {
    Start,
    Symbol,
    Decimal,
    Hex,
    Binary,
};

pub fn load(self: *Tokenizer, gpa: Allocator, buffer: []const u8) !void {
    try self.buffer.ensureTotalCapacity(gpa, buffer.len);
    self.buffer.clearRetainingCapacity();
    _ = try self.buffer.appendSlice(gpa, buffer);
    self.seek = 0;
    self.end = buffer.len;
    self._needs_input = false;
}

pub fn append(self: *Tokenizer, gpa: Allocator, buffer: []const u8) !void {
    try self.buffer.appendSlice(gpa, buffer);
    self.end += buffer.len;
}

pub fn deinit(self: *Tokenizer, gpa: Allocator) void {
    self.buffer.deinit(gpa);
    self.seek = 0;
    self.end = 0;
    self._needs_input = false;
}

pub fn reset(self: *Tokenizer) void {
    self.seek = 0;
    self.end = self.buffer.items.len;
    self._needs_input = false;
}
pub fn next(self: *Tokenizer) ?Result {
    var start: usize = self.seek;
    var end: usize = self.seek;
    if (self.seek >= self.end) {
        return null;
    }
    const buf = self.buffer.items[0..self.end];
    state: switch (State.Start) {
        .Start => {
            if (self.seek >= self.end) return null;
            switch (buf[self.seek]) {
                0 => {
                    return null;
                },
                ' ', '\n', '\r', '\t' => {
                    self.seek += 1;
                    start = self.seek;
                    end = self.seek;
                    continue :state .Start;
                },
                '0'...'9' => {
                    continue :state .Decimal;
                },
                '#' => {
                    self.seek += 1;
                    start = self.seek;
                    continue :state .Decimal;
                },
                '$' => {
                    self.seek += 1;
                    start = self.seek;
                    continue :state .Hex;
                },
                '%' => {
                    self.seek += 1;
                    start = self.seek;
                    continue :state .Binary;
                },
                else => {
                    continue :state .Symbol;
                },
            }
        },
        .Symbol => {
            self.seek += 1;
            if (self.seek >= self.end) {
                end = self.seek;
                return Result{ .symbol = buf[start..end] };
            }
            switch (buf[self.seek]) {
                ' ', '\n', '\r', '\t', 0 => {
                    end = self.seek;
                    return Result{ .symbol = buf[start..end] };
                },
                else => {
                    continue :state .Symbol;
                },
            }
        },
        .Decimal => {
            self.seek += 1;
            if (self.seek >= self.end) {
                end = self.seek;
                const number: usize = fmt.parseInt(usize, buf[start..end], 10) catch {
                    return null;
                };
                return Result{ .number = number };
            }
            switch (buf[self.seek]) {
                '0'...'9' => {
                    continue :state .Decimal;
                },
                else => {
                    end = self.seek;
                    const number: usize = fmt.parseInt(usize, buf[start..end], 10) catch {
                        return null;
                    };
                    return Result{ .number = number };
                },
            }
        },
        .Hex => {
            self.seek += 1;
            if (self.seek >= self.end) {
                end = self.seek;
                const number: usize = fmt.parseInt(usize, buf[start..end], 16) catch {
                    return null;
                };
                return Result{ .number = number };
            }
            switch (buf[self.seek]) {
                '0'...'9', 'A'...'F', 'a'...'f' => {
                    continue :state .Hex;
                },
                else => {
                    end = self.seek;
                    const number: usize = fmt.parseInt(usize, buf[start..end], 16) catch {
                        return null;
                    };
                    return Result{ .number = number };
                },
            }
        },
        .Binary => {
            self.seek += 1;
            if (self.seek >= self.end) {
                end = self.seek;
                const number: usize = fmt.parseInt(usize, buf[start..end], 2) catch {
                    return null;
                };
                return Result{ .number = number };
            }
            switch (buf[self.seek]) {
                '0', '1' => {
                    continue :state .Binary;
                },
                else => {
                    end = self.seek;
                    const number: usize = fmt.parseInt(usize, buf[start..end], 2) catch {
                        return null;
                    };
                    return Result{ .number = number };
                },
            }
        },
    }
}

test "Tokenizer parses symbols and numbers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const input = "hello 123 $7B %1111011 world";
    var tokenizer = Tokenizer{};
    try tokenizer.load(allocator, input);
    defer tokenizer.deinit(allocator);

    const token1 = tokenizer.next() orelse unreachable;
    try std.testing.expect(mem.eql(u8, token1.symbol, "hello"));

    const token2 = tokenizer.next() orelse unreachable;
    try std.testing.expect(token2.number == 123);

    const token3 = tokenizer.next() orelse unreachable;
    try std.testing.expect(token3.number == 123);

    const token4 = tokenizer.next() orelse unreachable;
    try std.testing.expect(token4.number == 123);

    const token5 = tokenizer.next() orelse unreachable;
    try std.testing.expect(mem.eql(u8, token5.symbol, "world"));

    const token6 = tokenizer.next();
    try std.testing.expect(token6 == null);
}
