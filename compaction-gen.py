#!/bin/python3

import subprocess
import os
import sys
import random
import time


min_account_count = 2
min_transfer_count = 1000
max_account_count = 100000
max_transfer_count = 100000
max_account_batch_size = 8190
max_transfer_batch_size = 8190
max_account_batch_size = 30 # config=test_min
max_transfer_batch_size = 30


min_account_count = 50000
min_transfer_count = 50000
max_account_count = 200000
max_transfer_count = 200000


workdir = "workdir"
build_dir = os.getcwd()

timeout_s = 10 * 60

select_env_var = "COMP_SELECT"
look_env_var = "COMP_LOOK"
move_env_var = "COMP_MOVE"
level_env_var = "COMP_LEVEL"

selects = [
    "TLEAST",
    "TMOST",
    "VLEAST",
    "VMOST",
    "VMID",
    "HIGH_TVR",
    "LOW_TVR",
    "TMOST_VMOST",
    "TMOST_VLEAST",
    "TLEAST_VMOST",
    "TLEAST_VLEAST",
    "TMFREE_HIGH_TVR",
    "TMFREE_LOW_TVR",
    "TLFREE_HIGH_TVR",
    "TLFREE_LOW_TVR",
]

looks = [
    "NONE",
    "POST_SINGLE_NONFULL",
    "POST_SINGLE_LTHALF",
    "POST_SINGLE_GTHALF",
    "WITH_SINGLE_NONFULL",
    "WITH_SINGLE_LTHALF",
    "WITH_SINGLE_GTHALF",
    "POST_MULTI_NONFULL",
    "POST_MULTI_LTHALF",
    "POST_MULTI_GTHALF",
    "WITH_MULTI_NONFULL",
    "WITH_MULTI_LTHALF",
    "WITH_MULTI_GTHALF",
]

moves = [
    "NONE",
    "ANY",
    "FULL",
    "LTHALF",
    "GTHALF",
]

levels = [
    "SAME",
    "S2NO-LYES",
    #"S2NO-LSPARSE10",
]

explicit_configs = [
    ("TLEAST", "NONE", "NONE", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "FULL", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "FULL", "S2NO-LYES"),
]

use_explicit_configs = True

# current favorites
# C_TLFREE_LOW_TVR_L_NONE_M_LTHALF
# C_TLFREE_LOW_TVR_L_NONE_M_GTHALF
# C_TLFREE_LOW_TVR_L_NONE_M_FULL
# C_TLFREE_LOW_TVR_L_WITH_SINGLE_GTHALF_M_LTHALF
# C_TLFREE_LOW_TVR_L_WITH_SINGLE_GTHALF_M_GTHALF
# C_TLFREE_LOW_TVR_L_WITH_MULTI_NONFULL_M_FULL
# C_TLFREE_HIGH_TVR_L_WITH_SINGLE_NONFULL_M_LTHALF
# C_TLFREE_HIGH_TVR_L_WITH_SINGLE_NONFULL_M_GTHALF
# C_TLFREE_HIGH_TVR_L_WITH_SINGLE_LTHALF_M_FULL
# C_LOW_TVR_L_WITH_MULTI_LTHALF_M_FULL
# C_LOW_TVR_L_WITH_SINGLE_LTHALF_M_FULL
# C_LOW_TVR_L_NONE_M_LTHALF
# C_LOW_TVR_L_NONE_M_GTHALF
# C_LOW_TVR_L_NONE_M_FULL

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

def run_once(seed, select, look, move, level, benchmark_args):
    command = [
        f"{build_dir}/tigerbeetle",
        "benchmark",
    ]
    command += benchmark_args
    env = os.environ.copy()
    env[select_env_var] = select
    env[look_env_var] = look
    env[move_env_var] = move
    env[level_env_var] = level
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
            env=env,
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        print(f"timeout {seed}, {select}/{look}/{move} {benchmark_args}",
              file=sys.stderr)
        return

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

def build_config_list():
    configs = []
    for select in selects:
        for look in looks:
            for move in moves:
                for level in levels:
                    configs += [(select, look, move, level)]
    return configs

build_tigerbeetle()
os.chdir(workdir)

configs = []
if use_explicit_configs:
    configs = explicit_configs
else:
    configs = build_config_list()

rng = random.Random(time.time())
start_seed = rng.randint(0, 10000)
end_seed = start_seed + seeds_count

print(f"start seed: {start_seed}")

for seed in range(0, end_seed):
    faux_seed = seed - start_seed
    benchmark_args = gen_benchmark_args(seed)
    for (select, look, move, level) in configs:
        run_once(faux_seed, select, look, move, level, benchmark_args)
        #print(f"{select} {look} {move}")
    
