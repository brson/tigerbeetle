const std = @import("std");
const assert = std.debug.assert;

pub fn WindowedIteratorType(
    comptime ElementType: type,
    comptime IteratorType: type,
    comptime window_size: usize,
) type {

    assert(window_size > 0);

    return struct {
        const WindowedIterator = @This();
        const Window = [window_size]ElementType;

        inner: IteratorType,
        window: ?Window,

        pub fn init(inner: IteratorType) WindowedIterator {
            return WindowedIterator {
                .inner = inner,
                .window = null,
            };
        }

        pub fn next(self: *WindowedIterator) ?Window {
            // fixme would like to write this in the opposite branch order
            if (self.window) |*window| {
                const next_val: ElementType = self.inner.next() orelse return null;
                slice_shift_left(ElementType, window, next_val);
                return window.*;
            } else {
                var init_window: Window = undefined;
                var index: usize = 0;
                while (index < window_size) {
                    const next_val: ElementType = self.inner.next() orelse return null;
                    init_window[index] = next_val;
                    index += 1;
                }
                self.window = init_window;
                return init_window;
            }
        }
    };
}

// todo memcpy may be faster
fn slice_shift_left(comptime T: type, slice: []T, val: T) void {
    assert(slice.len > 0);
    var index: usize = 0;
    while (index < slice.len - 1) {
        slice[index] = slice[index + 1];
        index += 1;
    }
    slice[index] = val;
}
