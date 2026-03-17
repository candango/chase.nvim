const std = @import("std");

pub fn main() !void {
    std.debug.print("I am the secondary tool.\n", .{});
}

test "tool test" {
    try std.testing.expect(true);
}
