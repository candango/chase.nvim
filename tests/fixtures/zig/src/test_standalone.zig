const std = @import("std");

test "standalone soma" {
    try std.testing.expect(1 + 1 == 2);
}
