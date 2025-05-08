import sys
from enum import Enum
from random import Random
from types import SimpleNamespace
from pathlib import Path
import subprocess
import os

home = os.environ.get("HOME", "error")
zig = f"{home}/zig/build/stage3/bin/zig"

workdir = "./bench"
master_seed = 0

config = SimpleNamespace(
    account_count_min = 10,
    account_count_max = 1_000,
    account_distributions = [
        "uniform",
        "zipfian",
        "latest",
    ],
    account_batch_size_min = 1,
    account_batch_size_max = 30,
    transfer_count_min = 1_000,
    transfer_count_max = 50_000,
    transfer_hot_percent_min = 1,
    transfer_hot_percent_max = 100,
    transfer_batch_size_min = 1,
    transfer_batch_size_max = 30,
)

config = SimpleNamespace(
    account_count_min = 10,
    account_count_max = 10_000,
    account_distributions = [
        "uniform",
        "zipfian",
        "latest",
    ],
    account_batch_size_min = 1,
    account_batch_size_max = 8190,
    transfer_count_min = 50_000,
    transfer_count_max = 100_000_000,
    transfer_hot_percent_min = 1,
    transfer_hot_percent_max = 100,
    transfer_batch_size_min = 1,
    transfer_batch_size_max = 8190,
)

class Mode(Enum):
    Old = 1,
    New = 2,

def make_runconfig_seed(
        master_seed: int,
        index: int,
        config: SimpleNamespace,
):
    rng = Random(master_seed + index)
    return make_runconfig(rng, master_seed, index, config)

def make_runconfig(
        rng: Random,
        master_seed: int,
        index: int,
        config: SimpleNamespace
):
    seed = rng.randint(0, 1_000_000)
    account_count = rng.randint(config.account_count_min, config.account_count_max)
    account_distribution = rng.choice(config.account_distributions)
    account_batch_size = rng.randint(config.account_batch_size_min, config.account_batch_size_max)
    transfer_count = rng.randint(config.transfer_count_min, config.transfer_count_max)
    transfer_hot_percent = rng.randint(config.transfer_hot_percent_min, config.transfer_hot_percent_max)
    transfer_batch_size = rng.randint(config.transfer_batch_size_min, config.transfer_batch_size_max)

    return SimpleNamespace(
        master_seed=master_seed,
        index=index,
        seed=seed,
        account_count=account_count,
        account_distribution=account_distribution,
        account_batch_size=account_batch_size,
        transfer_count=transfer_count,
        transfer_hot_percent=transfer_hot_percent,
        transfer_batch_size=transfer_batch_size,
    )

def build():
    print("building tigerbeetle")
    sys.stdout.flush()
    code = subprocess.run([
        zig, "build", "-Drelease",
    ], check=True)

def setup():
    ensure_empty_directory(workdir)

def ensure_empty_directory(path: str):
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Directory '{path}' does not exist.")
    if not p.is_dir():
        raise NotADirectoryError(f"'{path}' is not a directory.")
    if any(p.iterdir()):
        raise ValueError(f"Directory '{path}' is not empty.")
    
def run_one(
        seed: int,
        index: int,
        runconfig: SimpleNamespace,
        mode: Mode,
):
    benchmark(runconfig, mode)
    res = inspect(runconfig)
    cleanup(runconfig)
    return res

def benchmark(
        runconfig: SimpleNamespace,
        mode: Mode,
):
    args = make_benchmark_args(runconfig)
    #print(f"benchmark args: {" ".join(args)}")
    print(f"args: {" ".join(args)}")
    sys.stdout.flush()
    env_vars = os.environ.copy()
    if mode == Mode.New:
        env_vars["NEW_MOVE_OPT"] = "1"
    subprocess.run(
        args,
        env=env_vars,
        check=True,
        capture_output=True,
    )

def db_file_name(
        runconfig: SimpleNamespace,
):
    return f"{workdir}/{runconfig.master_seed}.{runconfig.index}.bench.tb"
    
def make_benchmark_args(
        runconfig: SimpleNamespace,
):
    file_name = db_file_name(runconfig)
    return [
        "./tigerbeetle",
        "benchmark",
        f"--file={file_name}",
        f"--seed={runconfig.seed}",
        f"--account-count={runconfig.account_count}",
        f"--account-distribution={runconfig.account_distribution}",
        f"--account-batch-size={runconfig.account_batch_size}",
        f"--transfer-count={runconfig.transfer_count}",
        f"--transfer-hot-percent={runconfig.transfer_hot_percent}",
        f"--transfer-batch-size={runconfig.transfer_batch_size}",
    ]

def inspect(
        runconfig: SimpleNamespace,
):
    args = make_inspect_args(runconfig)
    #print(f"inspect args: {" ".join(args)}")
    result = subprocess.run(
        args,
        check=True,
        capture_output=True,
    )
    return parse_inspect(result.stdout)

def make_inspect_args(
        runconfig: SimpleNamespace,
):
    file_name = db_file_name(runconfig)
    return [
        "./tigerbeetle",
        "inspect",
        "grid",
        f"{file_name}",
    ]

def parse_inspect(stdout):
    stdout = stdout.decode("utf-8")
    lines = stdout.splitlines()
    kvs = {}
    for line in lines:
        kv = line.split("=")
        key = kv[0]
        val = kv[1]
        kvs[key] = val
    return kvs

def cleanup(
        runconfig: SimpleNamespace,
):
    file_name = db_file_name(runconfig)
    os.remove(file_name)

def compare(
        seed: int,
        index: int,
        runconfig: SimpleNamespace,
        res_old: dict[str, str],
        res_new: dict[str, str],
):
    blocks_free_old = int(res_old["free_set.blocks_free"])
    blocks_free_new = int(res_new["free_set.blocks_free"])
    blocks_acquired_old = int(res_old["free_set.blocks_acquired"])
    blocks_acquired_new = int(res_new["free_set.blocks_acquired"])
    blocks_released_old = int(res_old["free_set.blocks_released"])
    blocks_released_new = int(res_new["free_set.blocks_released"])

    print(f"blocks_free_new: {blocks_free_new}, blocks_free_old: {blocks_free_old}")
    print(f"blocks_acquired_new: {blocks_acquired_new}, blocks_acquired_old: {blocks_acquired_old}")
    print(f"blocks_released_new: {blocks_released_new}, blocks_released_old: {blocks_released_old}")
    sys.stdout.flush()

    blocks_free_what = What.Good if blocks_free_new > blocks_free_old else\
        What.Bad if blocks_free_new < blocks_free_old else What.Neutral
    blocks_acquired_what = What.Good if blocks_acquired_new < blocks_acquired_old else\
        What.Bad if blocks_acquired_new > blocks_acquired_old else What.Neutral
    blocks_released_what = What.Good if blocks_released_new > blocks_released_old else\
        What.Bad if blocks_released_new > blocks_released_old else What.Neutral

    print(f"blocks_free_what: {blocks_free_what}")
    print(f"blocks_acquired_what: {blocks_acquired_what}")
    print(f"blocks_released_what: {blocks_released_what}")
    sys.stdout.flush()
    
class What(Enum):
    Good = 1,
    Bad = 2,
    Neutral = 3,
        
def run_all(
        seed: int,
        config: SimpleNamespace,
):
    setup()
    build()
    for index in range(0, 1000):
        print(f"run #{index} (seed {seed})")
        sys.stdout.flush()
        runconfig = make_runconfig_seed(seed, index, config)
        res_old = run_one(seed, index, runconfig, Mode.Old)
        sys.stdout.flush()
        res_new = run_one(seed, index, runconfig, Mode.New)
        sys.stdout.flush()
        compare(
            seed,
            index,
            runconfig,
            res_old,
            res_new
        )
        sys.stdout.flush()

run_all(master_seed, config)
