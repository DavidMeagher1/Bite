const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const io = std.io;

const Tokenizer = @This();

// should i automatically parse integers?

buffer: ?[]const u8 = null,
seek: usize = 0,
end: usize = 0,

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

pub fn load(self: *Tokenizer, gpa: Allocator, reader: *io.Reader, limit: usize) !void {
    if (self.buffer) |buf| {
        gpa.free(buf);
    }
    const buffer = try gpa.alloc(u8, limit);
    const bytesRead = try reader.readSliceShort(buffer);
    self.buffer = buffer;
    self.seek = 0;
    self.end = bytesRead;
}

pub fn deinit(self: *Tokenizer, gpa: Allocator) void {
    if (self.buffer) |buf| {
        gpa.free(buf);
    }
    self.buffer = null;
    self.seek = 0;
    self.end = 0;
}

pub fn reset(self: *Tokenizer) void {
    self.seek = 0;
    if (self.buffer) |buf| {
        self.end = buf.len;
    } else {
        self.end = 0;
    }
}

pub fn next(self: *Tokenizer) ?Result {
    var start: usize = self.seek;
    var end: usize = self.seek;
    if (self.seek >= self.end or self.buffer == null) {
        return null;
    }
    const buf = self.buffer.?;
    state: switch (State.Start) {
        .Start => {
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
    const gpa = std.heap.page_allocator;
    const input = "hello 123 $7B %1111011 world";
    var reader = std.io.Reader.fixed(input);
    var tokenizer = Tokenizer{};
    try tokenizer.load(gpa, &reader, input.len);
    defer tokenizer.deinit(gpa);

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
