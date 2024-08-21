//! The algorithm here is based on
//! "Quickly Generating Billion-Record Synthetic Databases", Jim Gray et al, SIGMOD 1994,
//! and its implementation in YCSB's ZipfianGenerator.java.
//! Note that the code listing in the paper
//! has multiple critical typos that the YCSB implementation
//! corrects for.
//! The paper is derived from Knuth volume 3, which I have not read.
//! Note that the random numbers returned by this generator start from 0,
//! while the ones in the paper start at 1, and in the YCSB generator from
//! an arbitrary range start.

const std = @import("std");
const assert = @import("std").debug.assert;
const Random = @import("std").Random;
const math = @import("std").math;

pub const ZipfianGenerator = struct {
    const Self = @This();

    theta: f64,

    n: u64,
    zetan: f64,

    pub fn init(items: u64) ZipfianGenerator {
        const theta_default = 0.99; // per YCSB
        return ZipfianGenerator.init(items, theta_default);
    }

    /// `theta` is the "skew" and is greater than 0 and less than 1;
    /// YCSB uses 0.99; values greater than 1 seem to work but it's not clear
    /// if they are valid.
    pub fn init_theta(items: u64, theta: f64) ZipfianGenerator {
        return ZipfianGenerator {
            .theta = theta,
            .n = items,
            .zetan = zeta(items, theta),
        };
    }

    pub fn next(self: *const Self, rng: *Random) u64 {
        const nf: f64 = @floatFromInt(self.n);
        const alpha = 1.0 / (1.0 - self.theta);
        const eta = (1.0 - math.pow(f64, 2.0 / nf, 1.0 - self.theta))
            / (1.0 - zeta(2.0, self.theta) / self.zetan);

        const u = rng.float(f64);
        const uz = u * self.zetan;

        if (uz < 1.0) {
            return 0;
        }

        if (uz < 1.0 + math.pow(f64, 0.5, self.theta)) {
            return 1;
        }

        return @as(u64, @intFromFloat(
            nf * math.pow(f64, eta * u - eta + 1.0, alpha)
        ));
    }

    pub fn add_items(self: *Self, new_items: u64) void {
        const items = self.n + new_items;
        self.* = .{
            .theta = self.theta,
            .n = items,
            .zetan = zeta(items, self.theta),
        };
    }

    pub fn probability(self: *const Self, item: u64) f64 {
        assert(item < self.n);
        const itemf: f64 = @floatFromInt(item);
        return (1.0 / self.zetan) * (1.0 / math.pow(f64, itemf + 1, self.theta));
    }
};

fn zeta(n: u64, theta: f64) f64 {
    var i: u64 = 1;
    var ans: f64 = 0.0;
    while (i <= n) : (i += 1) {
        const ifl: f64 = @floatFromInt(i);
        ans += math.pow(f64, 1.0 / ifl, theta);
    }
    return ans;
}

fn zeta_incr(prev_n: u64, addtl_n: u64, prev_zetan: f64, theta: f64) f64 {
    const new_n = prev_n + addtl_n;
    var i = prev_n + 1;
    var ans = prev_zetan;
    while (i <= new_n) : (i += 1) {
        const ifl: f64 = @floatFromInt(i);
        ans += math.pow(f64, 1.0 / ifl, theta);
    }
    return ans;
}

pub const ShuffledZipfian = struct {
};

test "zipfian" {
    var rng = std.Random.Pcg.init(0);
    const items = 10000;
    var zipf = ZipfianGenerator.init_theta(items, 1.1);

    var i: u64 = 0;
    var pcum: f64 = 0.0;
    while (i < items) : (i += 1) {
        const prob = zipf.probability(i);
        pcum += prob;
        std.debug.print("{} {d:.4} {d:.4}\n", .{ i, pcum, prob });
        if (pcum > 0.8 or prob < 0.001) {
            break;
        }
    }

    i = 0;
    while (i < 0) : (i += 1) {
        var rand = rng.random();
        const v = zipf.next(&rand);
        std.debug.print("{}\n", .{ v });
    }
}
