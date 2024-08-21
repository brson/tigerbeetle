const std = @import("std");
const assert = @import("std").assert;

const default_zipfian_constant: f64 = 0.99;

pub const ZipfianGenerator = struct {

    const Self = @This();
    
    items: u64,
    base: u64,
    zipfian_constant: f64,

    alpha: f64,
    zetan: f64,
    eta: f64,
    theta: f64,
    zeta2theta: f64,

    count_for_zeta: u64,

    rng: std.rand.DefaultPrng,

    pub fn init(seed: u64, min: u64, max: u64) ZipfianGenerator {
        return ZipfianGenerator.init_with_zipfian_constant(
            seed, min, max, default_zipfian_constant,
        );
    }

    fn init_with_zipfian_constant(
        seed: u64,
        min: u64,
        max: u64,
        zipfian_constant: f64,
    ) ZipfianGenerator {
        const zetan = zetastatic(max - min + 1, zipfian_constant);
        return ZipfianGenerator.init_with_zetan(
            seed, min, max, zipfian_constant, zetan,
        );
    }

    fn init_with_zetan(
        seed: u64,
        min: u64,
        max: u64,
        zipfian_constant: f64,
        zetan: f64,
    ) ZipfianGenerator {
        const items = max - min + 1;
        const base = min;

        const theta = zipfian_constant;
        const zeta2theta = zetastatic(2, theta);

        const alpha = 1.0 / (1.0 - theta);
        const count_for_zeta = items;

        const eta = (1 - std.math.pow(f64, 2.0 / @as(f64, @floatFromInt(items)), 1.0 - theta)) / (1.0 - zeta2theta / zetan);

        const rng = std.rand.DefaultPrng.init(seed);

        var zipfian = ZipfianGenerator {
            .items = items,
            .base = base,
            .zipfian_constant = zipfian_constant,
            .alpha = alpha,
            .zetan = zetan,
            .eta = eta,
            .theta = theta,
            .zeta2theta = zeta2theta,
            .count_for_zeta = count_for_zeta,
            .rng = rng,
        };

        _ = zipfian.next_value();

        return zipfian;
    }

    pub fn next_value(self: *Self) u64 {
        return self.next_value_(self.items);
    }

    fn next_value_(self: *Self, itemcount: u64) u64 {
        if (itemcount != self.count_for_zeta) {
            if (itemcount > self.count_for_zeta) {
                self.zetan = self.zeta(
                    self.count_for_zeta,
                    itemcount,
                    self.theta,
                    self.zetan,
                );
                self.eta = (1 - std.math.pow(f64, 2.0 / @as(f64, @floatFromInt(self.items)), 1.0 - self.theta)) / (1.0 - self.zeta2theta / self.zetan);
            } else {
                @panic("item count decrease not allowed");
            }
        }

        const u = self.rng.random().float(f64);
        const uz = u * self.zetan;

        if (uz < 1.0) {
            return self.base;
        }

        if (uz < 1.0 + std.math.pow(f64, 0.5, self.theta)) {
            return self.base + 1;
        }

        const ret = self.base + @as(u64, @intFromFloat(@as(f64, @floatFromInt(itemcount)) * std.math.pow(f64, self.eta * u - self.eta + 1.0, self.alpha)));
        return ret;
    }

    fn zeta(self: *Self, st: u64, n: u64, thetaval: f64, initialsum: f64) f64 {
        self.count_for_zeta = n;
        return zetastatic_(st, n, thetaval, initialsum);
    }
};

fn zetastatic(n: u64, theta: f64) f64 {
    return zetastatic_(0, n, theta, 0);
}

fn zetastatic_(
    st: u64, n: u64, theta: f64, initialsum: f64,
) f64 {
    var sum = initialsum;
    var i = st;
    while (i < n) : (i += 1) {
        sum += 1 / std.math.pow(f64, @floatFromInt(i + 1), theta);
    }
    return sum;
}

// Precomputed for default_zipfian_constant and item_count, per ycsb
const default_zetan: f64 = 26.46902820178302;
const item_count: u64 = 10000000000;

pub const ScrambledZipfianGenerator = struct {

    const Self = @This();

    gen: ZipfianGenerator,
    min: u64,
    itemcount: u64,

    pub fn init(
        seed: u64,
        min: u64,
        max: u64,
    ) ScrambledZipfianGenerator {
        assert(min <= max);
        assert(max < std.math.maxInt(u64));

        return ScrambledZipfianGenerator {
            .gen = ZipfianGenerator.init_with_zetan(
                seed,
                min,
                max,
                default_zipfian_constant,
                default_zetan,
            ),
            .min = min,
            .itemcount = max - min + 1,
        };
    }

    pub fn next_value(self: *Self) u64 {
        const v = self.gen.next_value();
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, v);
        const hashed = hasher.final();
        const scrambled = self.min + hashed % self.itemcount;
        return scrambled;
    }
};

test "zipfian" {
    var rng = ZipfianGenerator.init(0, 0, 1000);

    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        const v = rng.next_value();
        std.debug.print("{}\n", .{ v });
    }
}
