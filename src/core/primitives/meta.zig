const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Interp = @import("../interp.zig");
const Dictionary = @import("../dictionary.zig");
const registerPrimitive = @import("core.zig").registerPrimitive;

pub fn words(ctx: *Interp) !void {
    var current_index = ctx.dict.last;
    while (true) {
        const info_index = current_index.add(Dictionary.INFO_OFFSET);
        const info = try ctx.dict.getInfo(info_index);
        if (!info.smuged) {
            const name_index = current_index.add(Dictionary.NAME_OFFSET);
            const word_name = try ctx.dict.getName(name_index, info.name_length);
            std.debug.print("{s}\n", .{word_name});
        }
        const last_index = current_index;
        current_index = try ctx.dict.getLink(current_index);
        if (current_index == last_index) break;
    }
}

pub fn addMetaPrimitives(dict: *Dictionary, gpa: Allocator) !void {
    try registerPrimitive(dict, gpa, "WORDS", words, false);
}
