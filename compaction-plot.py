#!/bin/python3

import csv
import matplotlib.pyplot as plt
import math

statsfile = "compaction-stats.csv"

colors_12 = [
    "#db4240",
    "#6bbd3d",
    "#a247e0",
    "#5fa45d",
    "#d04fb2",
    "#cba83e",
    "#7d6ac8",
    "#897f3c",
    "#6e90cb",
    "#c67048",
    "#49b0a1",
    "#c26388"
]

colors_60 = [
    "#7286e8",
    "#51d431",
    "#962fec",
    "#4ec54b",
    "#d038f0",
    "#5da72b",
    "#7147e7",
    "#a5c030",
    "#e734db",
    "#6bc36b",
    "#9a36c6",
    "#409f55",
    "#c94dcf",
    "#48cd94",
    "#df36ad",
    "#3e7a2f",
    "#4c5ee3",
    "#db9b2c",
    "#a069e4",
    "#7c9b36",
    "#525ec5",
    "#c2ab3a",
    "#824ead",
    "#a2c160",
    "#df74d2",
    "#7b8125",
    "#e93280",
    "#4fab90",
    "#e74728",
    "#4ac1c2",
    "#cd3446",
    "#53b3de",
    "#e17d1e",
    "#4a62ad",
    "#e47c4b",
    "#3772a4",
    "#b2451e",
    "#769dde",
    "#9f6e26",
    "#ba93e1",
    "#596624",
    "#ad3b8b",
    "#86b075",
    "#d65484",
    "#327750",
    "#ab6cad",
    "#d69b54",
    "#844b8c",
    "#c9b578",
    "#6f679d",
    "#775f1f",
    "#d893c5",
    "#9b8e52",
    "#985275",
    "#de967a",
    "#a04359",
    "#95623e",
    "#dd8698",
    "#a6513b",
    "#e16e68"
]

markers = [
    'o',  # Circle
    '^',  # Triangle Up
    'v',  # Triangle Down
    '<',  # Triangle Left
    '>',  # Triangle Right
    's',  # Square
    'p',  # Pentagon
    '*',  # Star
    '+',  # Plus
    'x',  # Cross
    'D',  # Diamond
    'd',  # Thin Diamond
    '|',  # Vertical Line
    '_',  # Horizontal Line
    'H',  # Hexagon 1
    'h',  # Hexagon 2
    'P',  # Plus (filled)
    'X'   # Cross (filled)
]

def load_data(statsfile):
    data = []

    with open(statsfile) as csvfile:
        csvreader = csv.reader(csvfile)

        for row in csvreader:
            seed = int(row[0])
            config = row[1].strip()
            blocks_created = int(row[2])
            blocks_active = int(row[3])
            data += [[seed, config, blocks_created, blocks_active]]

    return data

def trim_incomplete_data(data):
    configs_per_seed = 0;
    for row in data:
        if row[0] == 0:
            configs_per_seed += 1

    new_row_count = math.floor(len(data) / configs_per_seed) * configs_per_seed

    return data[:new_row_count]

def build_views(data):
    seeds = {}
    for row in data:
        if not row[0] in seeds:
            seeds[row[0]] = []
        seed = seeds[row[0]]
        seed += [row]

        configs = {}
    for row in data:
        if not row[1] in configs:
            configs[row[1]] = []
        config = configs[row[1]]
        config += [row]

    return seeds, configs


def normalize(data):
    normalized = []
    seeds, configs = build_views(data)

    for seed in seeds.values():
        blocks_created_total = 0
        blocks_active_total = 0
        blocks_created_max = 0
        blocks_active_max = 0
        for row in seed:
            blocks_created_total += row[2]
            blocks_active_total += row[3]
            blocks_created_max = max(blocks_created_max, row[2])
            blocks_active_max = max(blocks_active_max, row[3])
        blocks_created_mean = blocks_created_total / len(seed)
        blocks_active_mean = blocks_active_total / len(seed)
        #blocks_created_scale = 1 / blocks_created_max * 2
        #blocks_active_scale = 1 / blocks_active_max * 2
        blocks_created_scale = 1
        blocks_active_scale = 1
        for row in seed:
            blocks_created_norm = (row[2] - blocks_created_mean) * blocks_created_scale
            blocks_active_norm = (row[3] - blocks_active_mean) * blocks_active_scale
            normalized += [[
                row[0],
                row[1],
                blocks_created_norm,
                blocks_active_norm,
            ]]

    return normalized

data = load_data(statsfile)
data = trim_incomplete_data(data)
normalized = normalize(data)


scatter_data = normalized




colors = colors_12

if len(scatter_data) > 12:
    colors = colors_60



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



plt.figure(figsize=(16,9))


for i, cat in enumerate(categories):
    cat = categories[cat]
    plt.scatter(
        cat["blocks_created"],
        cat["blocks_active"],
        label=cat["name"],
        color=colors[i % len(colors)],
        marker=markers[i % len(markers)],
    )

plt.title("Write/Space of Compaction Strategies")
plt.xlabel("blocks_created")
plt.ylabel("blocks_active")
plt.subplots_adjust(right=0.72)
plt.legend(bbox_to_anchor=(1.01, 1), loc='upper left', borderaxespad=0.)
#plt.legend()
plt.grid(True)

plt.savefig("compaction-plot.png")
