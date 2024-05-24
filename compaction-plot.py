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
        kind = row[1].strip()
        blocks_created = int(row[2])
        blocks_active = int(row[3])
        data += [[kind, blocks_created, blocks_active]]

categories = {}

for row in data:
    if not row[0] in categories:
        categories[row[0]] = {
            "name": row[0],
            "blocks_created": [],
            "blocks_active": []
        }
    cat = categories[row[0]]
    cat["blocks_created"] += [row[1]]
    cat["blocks_active"] += [row[2]]

plt.figure(figsize=(8,6))

for i, cat in enumerate(categories):
    cat = categories[cat]
    plt.scatter(
        cat["blocks_created"],
        cat["blocks_active"],
        label=cat["name"],
        color=colors[i],
    )

plt.title("Write/Space of Compaction Strategies")
plt.xlabel("blocks_created")
plt.ylabel("blocks_active")
plt.legend()
plt.grid(True)

plt.savefig("compaction-plot.png")
