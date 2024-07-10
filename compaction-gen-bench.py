#!/bin/python3

# todo
#
# add move/look tunables
# add "full window look"

import subprocess
import os
import sys
import random

workdir = "workdir"
build_dir = os.getcwd()

select_env_var = "COMP_SELECT"
look_env_var = "COMP_LOOK"
move_env_var = "COMP_MOVE"

selects = [
    #"TLEAST",
    # "TMOST",
    "VLEAST",
    "VMOST",
    #"VMID",
    ##"HIGH_TVR",
    "LOW_TVR",
    # "TMOST_VMOST",
    # "TMOST_VLEAST",
    # "TLEAST_VMOST",
    # "TLEAST_VLEAST",
    # "TMFREE_HIGH_TVR",
    ##"TMFREE_LOW_TVR",
    # "TLFREE_HIGH_TVR",
    # "TLFREE_LOW_TVR",
]

looks = [
    "NONE",
    "POST_SINGLE_NONFULL",
    "POST_SINGLE_LTHALF",
    "POST_SINGLE_GTHALF",
    "WITH_SINGLE_NONFULL",
    "WITH_SINGLE_LTHALF",
    "WITH_SINGLE_GTHALF",
]

moves = [
    "NONE",
    "ANY",
    "FULL",
    "LTHALF",
    "GTHALF",
]

# favorites
# EX_VMOST
# EX_VMOST_LOOK
# EX_LOW_TVR
# EX_LOW_TVR_LOOK

events_max=100000
seeds_count=1000

def build_tigerbeetle():
    command = [
        "zig/zig",
        "build",
        "-Drelease",
        "-Dconfig=test_min",
    ]
    result = subprocess.run(
        command,
        text=True,
        check=True,
    )

def run_once(select, look, move, benchmark_args):
    command = [
        f"{build_dir}/tigerbeetle",
        "benchmark",
    ]
    command += benchmark_args
    env = os.environ.copy()
    env[select_env_var] = select
    env[look_env_var] = look
    env[move_env_var] = move
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

    min_account_count = 2
    min_transfer_count = 1000
    max_account_count = 100000
    max_transfer_count = 100000
    max_account_batch_size = 8190
    max_transfer_batch_size = 8190
    max_account_batch_size = 30 # config=test_min
    max_transfer_batch_size = 30

    #min_account_count = 10000
    #min_transfer_count = 10000
    max_account_count = 10000
    max_transfer_count = 10000
    #max_account_batch_size = 10
    #max_transfer_batch_size = 10

    account_count = rng.randint(min_account_count, max_account_count)
    transfer_count = rng.randint(min_transfer_count, max_transfer_count)
    account_batch_size = rng.randint(1, max_account_batch_size)
    transfer_batch_size = rng.randint(1, max_transfer_batch_size)
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

build_tigerbeetle()
os.chdir(workdir)

for seed in range(0, seeds_count):
    benchmark_args = gen_benchmark_args(seed)
    for select in selects:
        for look in looks:
            for move in moves:
                run_once(select, look, move, benchmark_args)
    
