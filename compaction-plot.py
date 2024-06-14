#!/bin/python3

import csv
import matplotlib.pyplot as plt
import numpy as np

statsfile = "compaction-stats.csv"

colors = [
    "#2f4f4f",
    "#228b22",
    "#7f0000",
    "#4b0082",
    "#ff8c00",
    "#00ff00",
    "#00ffff",
    "#ff00ff",
    "#ffff54",
    "#6495ed",
    "#ff69b4",
    "#ffe4c4",
]

data = []

with open(statsfile) as csvfile:
    csvreader = csv.reader(csvfile)

    for row in csvreader:
        seed = row[0]
        kind = row[1].strip()
        blocks_created = int(row[2])
        blocks_active = int(row[3])
        data += [[seed, kind, blocks_created, blocks_active]]

seeds = {}

for row in data:
    if not row[0] in seeds:
        seeds[row[0]] = []
    seed = seeds[row[0]]
    seed += [row]

normalized = []
    
for seed in seeds.values():
    blocks_created_total = 0
    blocks_active_total = 0
    for row in seed:
        blocks_created_total += row[2]
        blocks_active_total += row[3]
    blocks_created_mean = blocks_created_total / len(seed)
    blocks_active_mean = blocks_active_total / len(seed)
    for row in seed:
        normalized += [[
            row[0],
            row[1],
            row[2] - blocks_created_mean,
            row[3] - blocks_active_mean,
        ]]

scatter_data = normalized

categories = {}

for row in scatter_data:
    if not row[1] in categories:
        categories[row[1]] = {
            "name": row[1],
            "blocks_created": [],
            "blocks_active": []
        }
    cat = categories[row[1]]
    cat["blocks_created"] += [row[2]]
    cat["blocks_active"] += [row[3]]



linear_regressions = []

for cat in categories:
    cat = categories[cat]
    blocks_created = cat["blocks_created"]
    blocks_active = cat["blocks_active"]
    slope, intercept = np.polyfit(
        blocks_created,
        blocks_active,
        1,
    )

    x_fit = np.linspace(
        min(blocks_created),
        max(blocks_created),
        100,
    )
    y_fit = slope * x_fit + intercept
    linear_regressions += [(x_fit, y_fit)]




plt.figure(figsize=(8,6))

for i, cat in enumerate(categories):
    cat = categories[cat]
    plt.scatter(
        cat["blocks_created"],
        cat["blocks_active"],
        label=cat["name"],
        color=colors[i],
    )

if False:
    for i, (x_fit, y_fit) in enumerate(linear_regressions):
        plt.plot(
            x_fit,
            y_fit,
            color=colors[i],
        )
        
    
plt.title("Write/Space of Compaction Strategies")
plt.xlabel("blocks_created")
plt.ylabel("blocks_active")
plt.legend()
plt.grid(True)

plt.savefig("compaction-plot.png")
