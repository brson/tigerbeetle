// todo
//
// - overflows
// - fix "item" terminology
// - select zeta by hot percent
// - k-s test

//! Zipfian-distributed random number generation.
//!
//! In the Zipfian distribution a small percentage of candidate
//! items have a high probability of being selected, while most items
//! have very low probability of being selected.
//! It is commonly understood to model the "80-20" Pareto principle,
//! and to be a discreet version of the Pareto distribution,
//! and terminology related to both are often used interchangably.
//!
//! Zipfian numbers follow an inverse power law, where the 1st item
//! is selected with high probability, and subsequent items
//! quickly fall off in probability. The rate of the fall off
//! is tunable by the _skew_, also called `s`, or `theta`,
//! depending on the source.
//!
//! Reference:
//!
//! - https://en.wikipedia.org/wiki/Zipf's_law#Formal_definition
//!
//! Note that it is not actually possible to select a value for
//! theta that literally follows the "80-20" rule for arbitrary set sizes;
//! the proportion of items that cumulatively make up 80% probability will
//! change as the set grows.
//! A zipfian generator that can adaptively follow the 80-20 rule is left for future work.
//!
//! Here an "item" is a value from 0 to some maximum, which the caller
//! can treat as an index into some other array or application-specific
//! deterministic value generator.
//!
//! In practice these probabilities often need to be spread across e.g. a
//! table's keyspace, which involves some kind of mapping step from index to index.
//! Because that mapping is non-trivial to optimize, it is also provided here.
//!
//! The algorithm here is based on
//! "Quickly Generating Billion-Record Synthetic Databases", Jim Gray et al, SIGMOD 1994.
//! Per the paper it is adapted from Knuth vol 3.
//! This is also the algorithm used by YCSB's ZipfianGenerator.java.
//!
//! There are two generators here,
//! both of which generate random keys from 0 to a specified maximum.
//! In the basic `ZipfianGenerator`, key 0 has the highest probability,
//! 1 the next highest, etc.
//! The `ShuffledZipfian` generator instead spreads the distribution out
//! across the key space as if it were a shuffled deck.
//!
//! Both generators allow for the key space to grow (but not shrink),
//! dynamically recomputing the distribution. When the `ShuffledZipfian`
//! generator grows it acts as if each new key was inserted into the shuffled
//! deck randomly, preserving the relative probability of existing keys.
//!
//! Note that while the non-shuffled generator should pass a 2-sample Kolmogorov–Smirnov test;
//! the shuffled generator does not because the tail distribution is fudged.
//!
//! The comments in this file alternately refer to the values
//! generated as "values", "items", "indexes", or "keys", but all
//! mean "some value from 0 to n".

const std = @import("std");
const assert = @import("std").debug.assert;
const Random = @import("std").Random;
const math = @import("std").math;
const BoundedArray = @import("./bounded_array.zig").BoundedArray;

/// The default "skew" of the distribution.
const theta_default = 0.99; // per YCSB

/// Generates Zipfian-distributed numbers from 0 to a specified maximum.
///
/// The internal variables here are the same is in the paper;
/// the external intended to be more understandable to the user.
pub const ZipfianGenerator = struct {
    const Self = @This();

    theta: f64,

    /// The number of items in the set.
    n: u64,
    /// The Riemann zeta function calculated up to `n`,
    /// aka the "generalized harmonic number" of order `theta` for `n`.
    /// This is a pre-calculated factor in the probability of any particular item
    /// being selected.
    /// It is expensive to calculate for large but useful values of `n`,
    /// but can be calculated incrementally as `n` grows.
    zetan: f64,

    /// Create a generator from [0, 1) with `theta` equal to 0.99.
    pub fn init(items: u64) ZipfianGenerator {
        return ZipfianGenerator.init_theta(items, theta_default);
    }

    /// Create a generator from [0, 1) with given `theta`
    /// `theta` is the "skew" and is usually specified to be greater than 0 and less than 1,
    /// with YCSB using 0.99, though values greater than 1 also seem to generate reasonable
    /// distributions.
    pub fn init_theta(items: u64, theta: f64) ZipfianGenerator {
        assert(theta > 0.0);
        assert(theta != 1.0); // 1.0 does not behave reasonably.
        return ZipfianGenerator {
            .theta = theta,
            .n = items,
            .zetan = zeta(items, theta),
        };
    }

    pub fn next(self: *const Self, rng: *Random) u64 {
        assert(self.n > 0);

        // Math voodoo, copied straight from the paper,
        // which doesn't explain it, but claims it is from Knuth volume 3.

        const nf: f64 = @floatFromInt(self.n);

        // NB: These depend only on zetan and could be cached for a minor speedup.
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

    /// Grow the size of the random set.
    pub fn grow(self: *Self, new_items: u64) void {
        const items = self.n + new_items;
        const zetan_new = zeta_incr(self.n, new_items, self.zetan, self.theta);
        self.* = .{
            .theta = self.theta,
            .n = items,
            .zetan = zetan_new,
        };
    }

    /// The probability that an index will be chosen.
    fn probability(self: *const Self, item: u64) f64 {
        assert(item < self.n);
        const itemf: f64 = @floatFromInt(item);

        // Reference: https://en.wikipedia.org/wiki/Zipf's_law#Formal_definition
        //
        //   1      1
        // ----- * ---
        // zetan   k^s
        //
        // zetan is the generalized harmonic number of order "s" (theta) for `n`.
        // We add 1 to `k` because our items are 0-based but the math is 1-based.
        return (1.0 / self.zetan) * (1.0 / math.pow(f64, itemf + 1, self.theta));
    }

    /// Returns the numbef of items at which the cumulative distribution function (CDF - the
    /// probability of some value less than x being generated) is greater or equal to `prob`.
    ///
    /// If there is no such value, returns the total number of items.
    fn cumulative_distribution_items(self: *const Self, prob: f64) u64 {
        assert(prob >= 0.0 and prob <= 1.0);

        var idx: u64 = 0;
        var prob_sum: f64 = 0.0;
        while (idx < self.n) : (idx += 1) {
            prob_sum += self.probability(idx);
            if (prob_sum >= prob) {
                return idx + 1;
            }
        }

        return self.n;
    }

    /// The cumulative distribution function evaluated at `item`.
    fn cumulative_distribution_of(self: *const Self, item: u64) f64 {
        var idx: u64 = 0;
        var prob_sum: f64 = 0.0;
        while (idx <= item) : (idx += 1) {
            prob_sum += self.probability(idx);
        }

        return prob_sum;
    }
};

/// The Riemann zeta function up to `n`,
/// aka the "generalized harmonic number" of order 'theta' for `n`.
fn zeta(n: u64, theta: f64) f64 {
    var i: u64 = 1;
    var ans: f64 = 0.0;
    while (i <= n) : (i += 1) {
        const ifl: f64 = @floatFromInt(i);
        ans += math.pow(f64, 1.0 / ifl, theta);
    }
    return ans;
}

/// Incremental calculation of zeta.
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

/// Generates Zipfian-distributed numbers from 0 to maximum,
/// but the probabilities of each number are "shuffled",
/// not clustered around 0.
///
/// This is used to simulate typical data access patterns in
/// some keyspace, where a few keys are hot and most are cold.
///
/// This behaves as if it maintains a shuffled mapping
/// from every index to a different index. It is implemented
/// as suggested in the Jim Gray paper: we observe that
/// most items have very low probability of being selected;
/// we don't maintain a mapping for this set and instead treat
/// them as uniformly distributed; we keep only a small
/// mapping of the most probably selected items.
pub const ShuffledZipfian = struct {
    const Self = @This();

    const HotArray = BoundedArray(u64, hot_items_limit);

    /// We prefer to store enough hot items to fill the cumulative probablity here.
    /// Other items have uniform probability. In practice though most uses of this
    /// type first hit the `hot_items_min_probability_limit` below.
    const hot_items_cumulative_distribution_function = 0.8;
    /// The cutoff probability for hot items.
    /// Any index with a probability less than this has uniform probability.
    /// This is used to short circuit the CDF above for data sets / thetas with a particularly
    /// large hot item set.
    const hot_items_min_probability_limit = 0.0001;
    /// The maximum hot items we're willing to track.
    const hot_items_limit = 1024 * 4;

    gen: ZipfianGenerator,
    hot_items: HotArray,

    pub fn init(items: u64) ShuffledZipfian {
        return ShuffledZipfian.init_theta(items, theta_default);
    }

    pub fn init_theta(items: u64, theta: f64) ShuffledZipfian {
        return ShuffledZipfian {
            .gen = ZipfianGenerator.init_theta(items, theta),
            .hot_items = HotArray {},
        };
    }

    pub fn next(self: *const Self, rng: *Random) u64 {
        // First try to pick from a zipfian distribution
        // of hot items.
        const zipf_idx = self.gen.next(rng);
        if (zipf_idx < self.hot_items.count()) {
            const item = self.hot_items.get(zipf_idx);
            assert(item < self.gen.n);
            return item;
        }

        // Next pick from uniform distribution of all items.
        const uni_idx = rng.intRangeLessThan(u64, 0, self.gen.n);
        return uni_idx;
    }

    /// Grow the size of the random set.
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
                // NB: I believe this is biased as to which new items become hot items,
                // but it probably doesn't matter for our purposes.
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
        // If the probability of selecting indexes greater than hot_items.count is low,
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

        assert(cdf_items_max >= self.hot_items.count());

        var max = cdf_items_max;
        var hot_idx = self.hot_items.count();
        while (hot_idx < cdf_items_max) : (hot_idx += 1) {
            const prob = self.gen.probability(hot_idx);
            if (prob < hot_items_min_probability_limit) {
                assert(hot_idx > 0);
                max = hot_idx;
                break;
            }
        }

        // Hopefully hot items fit our array.
        assert(max <= hot_items_limit);

        return max;
    }
};

test "zeta_incr" {
    const Case = struct {
        n_start: u64,
        n_incr: u64,
        theta: f64,
    };
    const cases = [_] Case {
        .{
            .n_start = 0,
            .n_incr = 10,
            .theta = 0.99,
        },
        .{
            .n_start = 0,
            .n_incr = 10,
            .theta = 1.01,
        },
        .{
            .n_start = 100,
            .n_incr = 100,
            .theta = 0.99,
        },
    };

    for (cases) |case| {
        const n = case.n_start + case.n_incr;
        const zeta_expected = zeta(n, case.theta);
        const zeta_actual_start = zeta(case.n_start, case.theta);
        const zeta_actual = zeta_incr(
            case.n_start, case.n_incr,
            zeta_actual_start, case.theta,
        );
        assert(zeta_expected == zeta_actual);
    }
}

// Testing that the grow function correctly calculates zeta incrementally.
test "zipfian-grow" {
    // Need to try multiple times to ensure they don't both coincidentally
    // pick the likely 0 value.
    var i: u64 = 10;
    while (i < 100) : (i += 1) {
        const expected = brk: {
            var rng = std.Random.Pcg.init(0);
            var rand = rng.random();
            //const items = 10000;
            var zipf = ZipfianGenerator.init_theta(i, 0.9);
            break :brk zipf.next(&rand);
        };
        const actual = brk: {
            var rng = std.Random.Pcg.init(0);
            var rand = rng.random();
            //const items = 10000;
            var zipf = ZipfianGenerator.init_theta(1, 0.9);
            zipf.grow(i - 1);
            break :brk zipf.next(&rand);
        };
        assert(expected == actual);
    }
}

test "zipfian-smoke" {
    var rng = std.Random.Pcg.init(0);
    var rand = rng.random();
    //const items = 10000;
    var zipf = ZipfianGenerator.init_theta(100, 0.99);

    var i: u64 = 0;
    while (i < 10000000) : (i += 1) {
        zipf.grow(1);
        const n = zipf.next(&rand);
        _ = n;
        //std.debug.print("{}\n", .{n});
    }

    var szipf = ShuffledZipfian.init_theta(100, 0.99);
    //szipf.grow(100, &rand);

    var i_2: u64 = 1;
    while (i_2 < 1) : (i_2 += 1) {
        const n = szipf.next(&rand);
        _ = n;
        //std.debug.print("{}\n", .{n});
    }
}

// The "empirical cumulative distribution function"
fn ecdf(data: []const f64, value: f64) f64 {
    var count: usize = 0;
    for (data) |v| {
        if (v <= value) {
            count += 1;
        }
    }
    return @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(data.len));
}

fn ks_statistic(data1: []const f64, data2: []const f64) f64 {
    var max_diff: f64 = 0.0;
    for (data1) |v| {
        const ecdf1 = ecdf(data1, v);
        const ecdf2 = ecdf(data2, v);
        const diff = std.math.abs(ecdf1 - ecdf2);
        if (diff > max_diff) {
            max_diff = diff;
        }
    }
    return max_diff;
}

fn zipfian_probabilities(data: [] f64) void {
    for (data, 0..) |*item, idx| {
        _ = item;
        _ = idx;
    }
}

// Test that zipfian numbers pass the k-s test.
test "zipfian-fit" {
    const set_size = 1000;
    const gen_count = 10000;

    var zipf_probs = [_]f64{0.0} ** set_size;

    zipfian_probabilities(&zipf_probs);

    var gen_values = [_]u64{0.0} ** gen_count;

    var rng = std.Random.Pcg.init(0);
    var rand = rng.random();
    var zipf = ZipfianGenerator.init_theta(set_size, 0.99);

    var i: u64 = 0;
    while (i < gen_count) : (i += 1) {
        const n = zipf.next(&rand);
        gen_values[i] = n;
    }
}
