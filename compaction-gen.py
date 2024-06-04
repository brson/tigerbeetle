#!/bin/python3

import subprocess
import os
import sys
import random
import time

max_transaction_count = 100000
min_account_count = 2
min_transfer_count = 1000
max_account_count = 100000
max_transfer_count = 100000
max_account_batch_size = 8190
max_transfer_batch_size = 8190
max_account_batch_size = 30 # config=test_min
max_transfer_batch_size = 30


min_account_count = 5000
min_transfer_count = 5000
max_account_count = 20000
max_transfer_count = 20000

id_orders = [
    "sequential",
    #"random",
    #"reversed",
]

account_distributions = [
    #"uniform",
    "zipfian",
    #"latest",
]


workdir = "workdir"
build_dir = os.getcwd()

timeout_s = 10 * 60

select_env_var = "COMP_SELECT"
look_env_var = "COMP_LOOK"
move_env_var = "COMP_MOVE"
level_env_var = "COMP_LEVEL"

selects = [
    "TLEAST",
#    "TMOST",
#    "VLEAST",
#    "VMOST",
#    "VMID",
#    "HIGH_TVR",
    "LOW_TVR",
#    "TMOST_VMOST",
#    "TMOST_VLEAST",
#    "TLEAST_VMOST",
#    "TLEAST_VLEAST",
#    "TMFREE_HIGH_TVR",
#    "TMFREE_LOW_TVR",
    "TLFREE_HIGH_TVR",
    "TLFREE_LOW_TVR",
]

looks = [
    "NONE",
#    "POST_SINGLE_NONFULL",
#    "POST_SINGLE_LTHALF",
#    "POST_SINGLE_GTHALF",
    "WITH_SINGLE_NONFULL",
    "WITH_SINGLE_LTHALF",
#    "WITH_SINGLE_GTHALF",
#    "POST_MULTI_NONFULL",
#    "POST_MULTI_LTHALF",
#    "POST_MULTI_GTHALF",
    "WITH_MULTI_NONFULL",
    "WITH_MULTI_LTHALF",
#    "WITH_MULTI_GTHALF",
]

moves = [
    "NONE",
#    "ANY",
    "FULL",
    "LTHALF",
    "GTHALF",
]

levels = [
    "SAME",
    #"S2NO-LYES",
    #"S2NO-LSPARSE10",
]

use_explicit_configs = True

explicit_configs = [
    ("TLEAST", "NONE", "NONE", "SAME"),
    ("LOW_TVR", "NONE", "NONE", "SAME"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "NONE", "SAME"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "NONE", "SAME"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "NONE", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "NONE", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "NONE", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "NONE", "SAME"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "NONE", "SAME"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "NONE", "SAME"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "NONE", "SAME"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "NONE", "SAME"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "NONE", "SAME"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "NONE", "SAME"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "ANY", "SAME"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "ANY", "SAME"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "ANY", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "ANY", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "ANY", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "ANY", "SAME"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "ANY", "SAME"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "ANY", "SAME"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "ANY", "SAME"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "ANY", "SAME"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "ANY", "SAME"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "ANY", "SAME"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "FULL", "SAME"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "FULL", "SAME"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "FULL", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "FULL", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "FULL", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "FULL", "SAME"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "FULL", "SAME"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "FULL", "SAME"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "FULL", "SAME"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "FULL", "SAME"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "FULL", "SAME"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "FULL", "SAME"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "LTHALF", "SAME"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "LTHALF", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "LTHALF", "SAME"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "LTHALF", "SAME"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "LTHALF", "SAME"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "GTHALF", "SAME"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "GTHALF", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "GTHALF", "SAME"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "GTHALF", "SAME"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "GTHALF", "SAME"),
    ("LOW_TVR", "NONE", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "NONE", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "ANY", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "FULL", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "LTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_NONFULL", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_LTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_SINGLE_GTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_NONFULL", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_LTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_SINGLE_GTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_NONFULL", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_LTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "POST_MULTI_GTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_NONFULL", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_LTHALF", "GTHALF", "S2NO-LYES"),
    ("LOW_TVR", "WITH_MULTI_GTHALF", "GTHALF", "S2NO-LYES"),
]

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
    ]
    result = subprocess.run(
        command,
        text=True,
        check=True,
    )

def run_once(run_number, select, look, move, level, benchmark_args):
    command = [
        f"{build_dir}/tigerbeetle",
        "benchmark",
        "--query-count=1", # not testing queries
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
        print(f"timeout {run_number}, {select}/{look}/{move}/{level} {benchmark_args}",
              file=sys.stderr)
        return

    #print(result.stderr)
    csvline = parse_result(result.stderr)
    print(f"{run_number}, {csvline}, \"{benchmark_args}\"")
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

    min_transaction_count = min_account_count + min_transfer_count
    transaction_count = rng.randint(min_transaction_count, max_transaction_count)

    max_account_count_actual = min(max_transaction_count, max_account_count)
    account_count = rng.randint(min_account_count, max_account_count_actual)
    transactions_remaining = max_transaction_count - account_count
    max_transfer_count_actual = min(transactions_remaining, max_transfer_count)
    max_transfer_count_actual = max(max_transfer_count_actual, min_transfer_count)
    transfer_count = rng.randint(min_transfer_count, max_transfer_count_actual)

    # nb: account_count + transfer_count may exceed max_transaction_count by min_transfer_count

    account_batch_size = rng.randint(1, max_account_batch_size)
    transfer_batch_size = rng.randint(1, max_transfer_batch_size)
    id_order = rng.choice(id_orders)
    account_distribution = rng.choice(account_distributions)

    args = []
    args += [
        f"--seed={seed}",
        f"--account-count={account_count}",
        f"--transfer-count={transfer_count}",
        f"--account-batch-size={account_batch_size}",
        f"--transfer-batch-size={transfer_batch_size}",
        f"--id-order={id_order}",
        f"--account-distribution={account_distribution}",
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

print(f"start seed: {start_seed}",
      file=sys.stderr)

configs_per_bench = len(configs)

print(f"configs per bench: {configs_per_bench}",
      file=sys.stderr)
print(f"total benchmark seeds: {seeds_count}",
      file=sys.stderr)

runs_complete = 0
runs_time_total_s = 0.0

for seed in range(start_seed, end_seed):
    benchmark_args = gen_benchmark_args(seed)

    this_bench_runs_complete = 0
    this_bench_runs_time_total_s = 0.0

    for config_number, (select, look, move, level) in enumerate(configs):
        run_number = seed - start_seed

        start_time = time.perf_counter()

        run_once(run_number, select, look, move, level, benchmark_args)

        run_time = time.perf_counter() - start_time
        runs_complete += 1
        runs_time_total_s += run_time
        this_bench_runs_complete += 1
        this_bench_runs_time_total_s += run_time
        if config_number % 5 == 0:
            s_per_run = runs_time_total_s / runs_complete
            s_per_benchmark = configs_per_bench * s_per_run
            h_per_benchmark = s_per_benchmark / 60 / 60
            this_bench_s_per_run = this_bench_runs_time_total_s / this_bench_runs_complete
            this_bench_s_per_benchmark = configs_per_bench * this_bench_s_per_run
            this_bench_h_per_benchmark = this_bench_s_per_benchmark / 60 / 60
            time_to_complete_benchmark_s = this_bench_s_per_benchmark - this_bench_runs_time_total_s
            time_to_complete_benchmark_h = time_to_complete_benchmark_s / 60 / 60
            total_s = s_per_run * seeds_count * configs_per_bench
            total_h = total_s / 60 / 60
            time_to_complete_total_s = total_s - runs_time_total_s
            time_to_complete_total_h = total_s / 60 / 60
            print(f"total avg s per run: {s_per_run:.4f}; total avg bench time h: {h_per_benchmark:.4f}",
                  file=sys.stderr)
            print(f"this bench ave s per run: {this_bench_s_per_run:.4f}; this bench avg bench time h: {this_bench_h_per_benchmark:.4f}",
                  file=sys.stderr)
            print(f"est time to complete this bench s: {time_to_complete_benchmark_s:.4f}; h: {time_to_complete_benchmark_h:.4f}",
                  file=sys.stderr)
            print(f"est time to complete experiment s: {time_to_complete_total_s:.4f}; h: {time_to_complete_total_h:.4f}",
                  file=sys.stderr)
            print(f"est total experiment time s: {total_s:.4f}; h: {total_h:.4f}",
                  file=sys.stderr)
