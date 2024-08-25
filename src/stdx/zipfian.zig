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
const BoundedArray = @import("./bounded_array.zig").BoundedArray;

const theta_default = 0.99; // per YCSB

pub const ZipfianGenerator = struct {
    const Self = @This();

    theta: f64,

    n: u64,
    zetan: f64,

    pub fn init(items: u64) ZipfianGenerator {
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

    pub fn grow(self: *Self, new_items: u64) void {
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

    /// Returns the numbef of items which the cumulative distribution function (CDF - the
    /// probability of some value less than x being generated) is greater or equal to `prob`.
    ///
    /// If there is no such value, returns `n`.
    pub fn cumulative_distribution_items(self: *const Self, prob: f64) u64 {
        assert(prob >= 0.0 and prob <= 1.0);

        var idx: u64 = 0;
        var prob_cum: f64 = 0.0;
        while (idx < self.n) : (idx += 1) {
            prob_cum += self.probability(idx);
            if (prob_cum >= prob) {
                return idx + 1;
            }
        }

        return self.n;
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

/// We want to store enough hot items to fill the cumulative probablity here.
/// Other items have uniform probability.
const hot_items_cumulative_distribution_function = 0.8;
/// The cutoff probability for hot items.
/// Any index with a probability less than this has uniform probability.
/// This is used to short circuit the CDF above for data sets / thetas with a particularly
/// large hot item set.
const hot_items_min_probability_limit = 0.001;
const hot_items_limit = 1024;

pub const ShuffledZipfian = struct {
    const Self = @This();

    const HotArray = BoundedArray(u64, hot_items_limit);

    gen: ZipfianGenerator,
    hot_items: HotArray,

    pub fn init() ShuffledZipfian {
        return ShuffledZipfian.init(theta_default);
    }

    pub fn init_theta(theta: f64) ShuffledZipfian {
        return ShuffledZipfian {
            .gen = ZipfianGenerator.init_theta(0, theta),
            .hot_items = HotArray {},
        };
    }

    pub fn grow(self: *Self, new_items: u64, rng: *Random) void {
        const old_n = self.gen.n;
        const new_n = old_n + new_items;

        self.gen.grow(new_items);

        assert(self.gen.n == new_n);

        const hot_items_count_max = self.hot_items_max();

        assert(hot_items_count_max > 0);
        assert(hot_items_count_max <= new_n);

        // Shuffle each new item into deck of items.
        // If it's a hot item we'll track it, if not discard it.
        const start_idx = old_n;
        const end_idx = new_n;
        var idx = start_idx;
        while (idx < end_idx) : (idx += 1) {
            if (self.hot_items.count() < hot_items_count_max) {
                const pos_actual = rng.intRangeAtMost(u64, 0, self.hot_items.count());
                self.hot_items.insert_assume_capacity(pos_actual, idx);
            } else {
                const pos_init = rng.intRangeLessThan(u64, 0, new_n);
                if (pos_init < hot_items_count_max) {
                    self.hot_items.truncate(hot_items_count_max - 1);
                    const pos_actual = rng.intRangeAtMost(u64, 0, self.hot_items.count());
                    self.hot_items.insert_assume_capacity(pos_actual, idx);
                }
            }
        }

        assert(self.hot_items.count() == hot_items_count_max);
    }

    fn hot_items_max(self: *Self) u64 {
        // If the probability of selecting indexes greater that hot_items.count is low,
        // then we don't need any more hot_items. This short-circuits calculating the
        // expensive cumulative distribution function.
        if (self.hot_items.count() > 0) {
            const cur_hot_min_probability = self.gen.probability(self.hot_items.count() - 1);
            if (cur_hot_min_probability < hot_items_min_probability_limit) {
                return self.hot_items.count();
            }
        }

        const cdf_items_max = self.gen.cumulative_distribution_items(
            hot_items_cumulative_distribution_function,
        );

        // Hopefully we've sized this array to fulfill any workload
        assert(cdf_items_max <= hot_items_limit);

        // Not sure if this is possible
        if (cdf_items_max < self.hot_items.count()) {
            return self.hot_items.count();
        }

        var hot_idx = self.hot_items.count();
        while (hot_idx < cdf_items_max) : (hot_idx += 1) {
            const prob = self.gen.probability(hot_idx);
            if (prob < hot_items_min_probability_limit) {
                assert(hot_idx > 0);
                return hot_idx;
            }
        }

        return cdf_items_max;
    }
};

test "zipfian" {
    var rng = std.Random.Pcg.init(0);
    var rand = rng.random();
    const items = 10000;
    var zipf = ZipfianGenerator.init_theta(items, 1.1);

    var i: u64 = 0;
    var pcum: f64 = 0.0;
    while (i < items) : (i += 1) {
        const prob = zipf.probability(i);
        pcum += prob;
        //std.debug.print("{} {d:.4} {d:.4}\n", .{ i, pcum, prob });
        if (pcum > 0.8 or prob < 0.001) {
            break;
        }
    }

    i = 0;
    while (i < 0) : (i += 1) {
        const v = zipf.next(&rand);
        std.debug.print("{}\n", .{ v });
    }

    var szipf = ShuffledZipfian.init_theta(1.0);
    szipf.grow(1000, &rand);
}
