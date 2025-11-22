const std = @import("std");
const testing = std.testing;
const Lexer = @This();

pub const Value = union(enum) {
    eoi: void,
    u_int: usize,
    s_int: isize,
    text: []const u8,
};

source: ?[:0]const u8,
position: usize = 0,

pub fn reset(self: *Lexer, source: [:0]const u8) void {
    self.source = source;
    self.position = 0;
}

const State = enum {
    start,
    in_text,
};

fn nextText(self: *Lexer) []const u8 {
    var value: []const u8 = &[_]u8{};
    var start: usize = 0;
    var end: usize = 0;
    if (self.source == null) {
        return value;
    }
    const src = self.source.?;
    state: switch (State.start) {
        .start => switch (src[self.position]){
            0 => return &[_]u8{},
            ' ', '\n', '\r', '\t' => {
                self.position += 1;
                continue :state .start;
            },
            else => {
                start = self.position;
                continue :state .in_text;
            },
        },
        .in_text => {
            switch (src[self.position]) {
                0, ' ', '\n', '\r', '\t' => {
                    end = self.position;
                    value = src[start..end];
                    return value;
                },
                else => {
                    self.position += 1;
                    continue :state .in_text;
                },
            }
        },
    }
}

pub fn next(self: *Lexer) Value {
    const text = self.nextText();
    if (text.len == 0) {
        return Value{ .eoi = {} };
    }
    switch (text[0]) {
        '0'...'9' => {
            const num = std.fmt.parseInt(u64, text, 10) catch return Value{ .text = text };
            return Value{ .u_int = num };
        },
        '-' => {
            if (text.len > 1) {
                const num = std.fmt.parseInt(i64, text, 10) catch return Value{ .text = text };
                return Value{ .s_int = num };
            } else {
                return Value{ .text = text };
            }
        },
        '#' => {
            if (text.len > 1) {
                if (text[1] == '-') {
                    const num = std.fmt.parseInt(i64, text[2..], 10) catch return Value{ .text = text };
                    return Value{ .s_int = -num };
                } else {
                    const num = std.fmt.parseInt(u64, text[1..], 10) catch return Value{ .text = text };
                    return Value{ .u_int = num };
                }
            } else {
                return Value{ .text = text };
            }
        },
        '$' => {
            if (text.len > 1) {
                if (text[1] == '-') {
                    const num = std.fmt.parseInt(i64, text[2..], 16) catch return Value{ .text = text };
                    return Value{ .s_int = -num };
                } else {
                    const num = std.fmt.parseInt(u64, text[1..], 16) catch return Value{ .text = text };
                    return Value{ .u_int = num };
                }
            } else {
                return Value{ .text = text };
            }
        },
        '%' => {
            if (text.len > 1) {
                if (text[1] == '-') {
                    const num = std.fmt.parseInt(i64, text[2..], 2) catch return Value{ .text = text };
                    return Value{ .s_int = -num };
                } else {
                    const num = std.fmt.parseInt(u64, text[1..], 2) catch return Value{ .text = text };
                    return Value{ .u_int = num };
                }
            } else {
                return Value{ .text = text };
            }
        },
        else => {
            return Value{ .text = text };
        },
    }
}

test "lexer test" {
    const source = "  42 -17 $2A %101010 word1   word2  %-101010\n";
    var lexer = Lexer{
        .source = source,
    };
    const v1 = lexer.next();
    try std.testing.expectEqual(42, v1.u_int);
    const v2 = lexer.next();
    try std.testing.expectEqual(-17, v2.s_int);
    const v3 = lexer.next();
    try std.testing.expectEqual(42, v3.u_int);
    const v4 = lexer.next();
    try std.testing.expectEqual(42, v4.u_int);
    const v5 = lexer.next();
    try std.testing.expectEqualSlices(u8, v5.text, "word1");
    const v6 = lexer.next();
    try std.testing.expectEqualSlices(u8, v6.text, "word2");
    const v7 = lexer.next();
    try std.testing.expectEqual(-42, v7.s_int);
    const v8 = lexer.next();
    try std.testing.expectEqual(v8.eoi, {});
}
