#!/bin/python3

import subprocess
import os
import sys
import random

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

def run_once(strategy, benchmark_args):
    command = [
        "zig/zig",
        "build",
        "run",
        "-Drelease",
        "-Dconfig=production",
        "--",
        "benchmark",
    ]
    command += benchmark_args
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
    print(f"{seed}, {csvline}, \"{benchmark_args}\"")
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

def gen_benchmark_args(seed):
    rng = random.Random(seed)

    max_account_count = 1000000
    max_transfer_count = 1000000
    #max_account_count = 10
    #max_transfer_count = 100

    account_count = rng.randint(2, max_account_count)
    transfer_count = rng.randint(100, max_transfer_count)
    account_batch_size = rng.randint(1, 8190)
    transfer_batch_size = rng.randint(1, 8190)
    id_order = rng.choice([
        "sequential",
        "random",
        "reversed",
    ])

    args = []
    args += [
        f"--seed={seed}",
        f"--account-count={account_count}",
        f"--transfer-count={transfer_count}",
        f"--account-batch-size={account_batch_size}",
        f"--transfer-batch-size={transfer_batch_size}",
        f"--id-order={id_order}",
    ]

    return args

for seed in range(0, seeds_count):
    benchmark_args = gen_benchmark_args(seed)
    for strategy in strategies:
        run_once(strategy, benchmark_args)
    
