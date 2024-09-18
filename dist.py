#!/usr/bin/python3

import matplotlib.pyplot as plt
import numpy as np
from scipy import stats
import math
import random




#####

# The default "skew" of the distribution
theta_default = 0.99  # per YCSB

# Function to calculate the generalized harmonic number (zeta function)
def zeta(n, theta):
    return sum(1.0 / (i ** theta) for i in range(1, n + 1))

def zeta_incremental(n, new_items, zetan, theta):
    return zetan + sum(1.0 / ((n + i) ** theta) for i in range(1, new_items + 1))

class ZipfianGenerator:
    def __init__(self, items, theta=theta_default):
        assert theta > 0.0
        assert theta != 1.0
        self.theta = theta
        self.n = items
        self.zetan = zeta(items, theta)

    def next(self):
        assert self.n > 0

        # Math voodoo, copied from the paper
        alpha = 1.0 / (1.0 - self.theta)
        eta = (1.0 - math.pow(2.0 / float(self.n), 1.0 - self.theta)) / (
            1.0 - zeta(2, self.theta) / self.zetan
        )

        u = random.random()
        uz = u * self.zetan

        if uz < 1.0:
            return 0

        if uz < 1.0 + math.pow(0.5, self.theta):
            return 1

        return int(float(self.n) * math.pow((eta * u) - eta + 1.0, alpha))

    def next_targeted_absolute(self, hot_items, hot_probability_fraction):
        assert hot_items >= 0
        assert hot_items <= self.n
        assert hot_probability_fraction >= 0
        assert hot_probability_fraction <= 1

        hot_random = random.random()
        assert(0 <= hot_random <= 1)

        need_hot = hot_random <= hot_probability_fraction
        #todo

    def next_targeted_fraction(self, hot_items_fraction, hot_probability_fraction):
        pass

    def grow(self, new_items):
        items = self.n + new_items
        zetan_new = zeta_incremental(self.n, new_items, self.zetan, self.theta)
        self.n = items
        self.zetan = zetan_new

    def probability(self, item):
        assert item < self.n
        return (1.0 / self.zetan) * (1.0 / math.pow(item + 1, self.theta))

    def cumulative_distribution_items(self, cdf_probability):
        assert 0.0 <= cdf_probability <= 1.0

        index = 0
        probability_sum = 0.0
        while index < self.n:
            probability_sum += self.probability(index)
            if probability_sum >= cdf_probability:
                return index + 1
            index += 1

        return self.n



#####



def rank_data(data):
    """
    Rank the data based on frequency.
    """
    unique, counts = np.unique(data, return_counts=True)
    frequency = dict(zip(unique, counts))
    sorted_freq = sorted(frequency.values(), reverse=True)
    ranks = np.arange(1, len(sorted_freq) + 1)
    return ranks, sorted_freq

def zipf_expected_frequencies(n, alpha):
    """
    Calculate expected frequencies for a Zipf distribution.
    """
    harmonic_number = np.sum(1.0 / np.arange(1, n + 1)**alpha)
    expected_freq = (1.0 / np.arange(1, n + 1)**alpha) / harmonic_number
    return expected_freq

def test_zipfian(data, alpha, setsize):
    """
    Test whether the dataset follows a Zipfian distribution.
    """
    ranks, observed_freq = rank_data(data)
    expected_freq = zipf_expected_frequencies(setsize, alpha)
    
    # Normalize frequencies to make them comparable
    observed_freq = np.array(observed_freq) / np.sum(observed_freq)
    expected_freq = np.array(expected_freq) / np.sum(expected_freq)
    print(observed_freq)
    print(expected_freq)
    
    # Perform the Kolmogorov-Smirnov test
    return stats.ks_2samp(observed_freq, expected_freq);

def plot_zipfian_array(content, alpha, setsize):
    samples = [int(x) for x in content]

    buckets = [0] * 1000

    for i in range(0, len(samples)):
        item = samples[i]
        buckets[item] += 1

    buckets.sort()
    buckets.reverse()

    indexes = np.arange(len(buckets))
    indexes = indexes + 1

    plt.figure(figsize=(8, 6))

    # Plot using a log-log scale
    plt.loglog(indexes, buckets, marker='o', linestyle='-', color='b')

    # Add labels and title
    plt.xlabel('Bucket Index (log scale)')
    plt.ylabel('Count/Value (log scale)')
    plt.title('Log-Log Plot of Bucket Indexes vs. Counts')

    # Optionally, you can add gridlines
    plt.grid(True, which="both", ls="--")
    plt.savefig('log_log_plot.png', dpi=300, bbox_inches='tight')

    res = test_zipfian(samples, alpha, setsize)
    print(f"KS Statistic: {res}")

def plot_dist_file(filename, alpha, setsize):
    with open(filename, 'r') as file:
        content = file.read().split()
        plot_zipfian_array(content, alpha, setsize)

#plot_dist_file('dist.txt', 0.99, 10)

gen = ZipfianGenerator(100)
for _ in range(0, 100):
    val = gen.next()
    print(f"{val}")
