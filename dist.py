#!/usr/bin/python3

import matplotlib.pyplot as plt
import numpy as np
from scipy import stats

with open('dist.txt', 'r') as file:
    content = file.read().split()
    
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

#ranked = rank_data(samples)
#print(ranked)

res = test_zipfian(samples, 0.99, 100)
print(f"KS Statistic: {res}")


