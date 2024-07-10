#!/bin/python3

import csv
import matplotlib.pyplot as plt
import numpy as np

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



blocks_created_total_all = 0
blocks_active_total_all = 0
blocks_created_max_all = 0
blocks_active_max_all = 0
for seed in seeds.values():
    for row in seed:
        blocks_created_total_all += row[2]
        blocks_active_total_all += row[3]
        blocks_created_max_all = max(blocks_created_max_all, row[2])
        blocks_active_max_all = max(blocks_active_max_all, row[2])
blocks_created_mean_all = blocks_created_total_all / len(data)
blocks_active_mean_all = blocks_active_total_all / len(data)
blocks_created_scale_all = 1 / blocks_created_max_all * 2
blocks_active_scale_all = 1 / blocks_active_max_all * 2
        

normalized = []


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
    #blocks_created_scale = 1 / blocks_created_max_all * 2
    #blocks_active_scale = 1 / blocks_active_max_all * 2
    for row in seed:
        blocks_created_norm = (row[2] - blocks_created_mean) * blocks_created_scale
        blocks_active_norm = (row[3] - blocks_active_mean) * blocks_active_scale
        #blocks_created_norm = (row[2] - blocks_created_mean_all) * blocks_created_scale_all
        #blocks_active_norm = (row[3] - blocks_active_mean_all) * blocks_active_scale_all
        normalized += [[
            row[0],
            row[1],
            blocks_created_norm,
            blocks_active_norm,
        ]]



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



# linear_regressions = []

# for cat in categories:
#     cat = categories[cat]
#     blocks_created = cat["blocks_created"]
#     blocks_active = cat["blocks_active"]
#     slope, intercept = np.polyfit(
#         blocks_created,
#         blocks_active,
#         1,
#     )

#     x_fit = np.linspace(
#         min(blocks_created),
#         max(blocks_created),
#         100,
#     )
#     y_fit = slope * x_fit + intercept
#     linear_regressions += [(x_fit, y_fit)]




plt.figure(figsize=(16,9))


for i, cat in enumerate(categories):
    cat = categories[cat]
    plt.scatter(
        cat["blocks_created"],
        cat["blocks_active"],
        label=cat["name"],
        color=colors[i],
        marker=markers[i % len(markers)],
    )

# for i, (x_fit, y_fit) in enumerate(linear_regressions):
#     plt.plot(
#         x_fit,
#         y_fit,
#         color=colors[i],
#     )
        
    
plt.title("Write/Space of Compaction Strategies")
plt.xlabel("blocks_created")
plt.ylabel("blocks_active")
plt.subplots_adjust(right=0.72)
plt.legend(bbox_to_anchor=(1.01, 1), loc='upper left', borderaxespad=0.)
#plt.legend()
plt.grid(True)

plt.savefig("compaction-plot.png")
