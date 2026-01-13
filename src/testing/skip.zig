const std = @import("std");

/// Skip test unless TIGERBEETLE_RUN_EXPENSIVE_TESTS is set when replica_count > 1.
pub fn skipIfExpensive(replica_count: u8) error{SkipZigTest}!void {
    if (replica_count > 1 and std.posix.getenv("TIGERBEETLE_RUN_EXPENSIVE_TESTS") == null) {
        return error.SkipZigTest;
    }
}

/// Skip test unconditionally unless TIGERBEETLE_RUN_EXPENSIVE_TESTS is set.
pub fn skipIfExpensiveAlways() error{SkipZigTest}!void {
    if (std.posix.getenv("TIGERBEETLE_RUN_EXPENSIVE_TESTS") == null) {
        return error.SkipZigTest;
    }
}
