#!/bin/python3

import subprocess
import os
import sys

strat_env_var = "COMP_STRAT"
strategies = [
    "EX_TLEAST",
    "EX_TMOST",
    "EX_HIGH_TVR",
    "EX_LOW_TVR",
    "EX_TMOST_VMOST",
    "EX_TMOST_VLEAST",
    "EX_TLEAST_VMOST",
    "EX_TLEAST_VLEAST",
    "EX_TMFREE_HIGH_TVR",
    "EX_TMFREE_LOW_TVR",
    "EX_TLFREE_HIGH_TVR",
    "EX_TLFREE_LOW_TVR",
]
events_max=100000
seeds_count=1000

def run_once(seed, strategy):
    command = [
        "zig/zig",
        "build",
        "fuzz",
        "--",
        f"--events-max={events_max}",
        "lsm_forest",
        f"{seed}",
    ]
    env = os.environ.copy()
    env[strat_env_var] = strategy
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
        env=env,
    )
    #print(result.stderr)
    csvline = parse_result(result.stderr)
    print(f"{seed}, {csvline}")
    sys.stdout.flush()

def parse_result(stderr):
    grab = False
    for line in stderr.splitlines():
        if line == "~compaction-stats~":
            grab = True
            continue
        if grab:
            return line
    raise Exception("no stats")
        
for seed in range(0, seeds_count):
    for strategy in strategies:
        run_once(seed, strategy)
    
