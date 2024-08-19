// Zipfian random number generation.
//
// Based on https://github.com/jonhoo/rust-zipf
//
// Other references:
//
// - Apache commons-rng's RejectionInversionZipfSampler.java,
//   which rust-zipf is based on
// - "Rejection-Inversion to Generate Variates from Monotone Discrete Distributions",
//   which Apache commons is based on
// - YCSB's ZipfianGenerator and ScrambledZipfianGenerator
// - "Quickly Generating Billion-Record Synthetic Databases",
//   which YCSB is based on
//
// The YCSB method may be faster, but it requires either a heavy
// startup computation; or a static precomputation but fixed item length.
// The YCSB code is also not particularly clean.
//
// "exponent" is also commonly called "alpha", or seemingly
// "theta" in the YCSB distribution, which sets it to 0.99.

const std = @import("std");
const assert = std.debug.assert;

pub const ZipfDistribution = struct {
    const Self = @This();

    num_elements: f64,
    exponent: f64,
    h_integral_x1: f64,
    h_integral_num_elements: f64,
    s: f64,

    pub fn init(
        num_elements: u64,
        exponent: f64,
    ) ZipfDistribution {
        assert(num_elements > 0);
        assert(exponent > 0.0);

        return ZipfDistribution {
            .num_elements = @floatFromInt(num_elements),
            .exponent = exponent,
            .h_integral_x1 = h_integral(
                1.5,
                exponent,
            ) - 1.0,
            .h_integral_num_elements = h_integral(
                @as(f64, @floatFromInt(num_elements)) + 0.5,
                exponent,
            ),
            .s = 2.0 - h_integral_inv(
                h_integral(2.5, exponent)
                    - h(2.0, exponent),
                exponent,
            ),
        };
    }

    pub fn next(self: *const Self, rng: *std.Random) u64 {
        const hnum = self.h_integral_num_elements;

        while (true) {
            const u = hnum + rng.float(f64) * (self.h_integral_x1 - hnum);
            const x = h_integral_inv(u, self.exponent);
            const k64 = @min(@max(x, 1.0), self.num_elements);
            const k = @max(1, @as(u64, @intFromFloat((k64 + 0.5))));
            if (
                (k64 - x <= self.s)
                    or (u >= h_integral(k64 + 0.5, self.exponent)
                            - h(k64, self.exponent))
            ) {
                return k;
            }
        }
    }
};

fn h_integral(x: f64, exponent: f64) f64 {
    const log_x = @log(x);
    return helper2((1.0 - exponent) * log_x) * log_x;
}

fn h(x: f64, exponent: f64) f64 {
    return @exp(-exponent * @log(x));
}

fn h_integral_inv(x: f64, exponent: f64) f64 {
    var t = x * (1.0 - exponent);
    if (t < -1.0) {
        t = -1.0;
    }
    return @exp(helper1(t) * x);
}

fn helper1(x: f64) f64 {
    if (@abs(x) > 1e-8) {
        return std.math.log1p(x) / x;
    } else {
        return 1.0 - x * (0.5 - x * (1.0 / 3.0 - 0.25 * x));
    }
}

fn helper2(x: f64) f64 {
    if (@abs(x) > 1e-8) {
        return std.math.expm1(x) / x;
    } else {
        return 1.0 + x * 0.5 * (1.0 + x * 1.0 / 3.0 * (1.0 + 0.25 * x));
    }
}

test "zipfian" {
    var rng = std.Random.Pcg.init(0);
    var rng2 = rng.random();
    var zipf = ZipfDistribution.init(100, 0.99);
    _ = zipf.next(&rng2);
}
