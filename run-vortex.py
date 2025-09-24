#!/usr/bin/env python3

import os
import platform
import subprocess
import sys
from pathlib import Path
import argparse
import io
import shutil

sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.detach(), encoding='utf-8')

DEFAULT_OUT_DIRECTORY = "./vortex-out"
DEFAULT_TEST_DURATION_SECONDS = 2
DEFAULT_REPLICA_COUNT = 1
DEFAULT_DISABLE_FAULTS = True

ZIG_CMD = os.environ.get("ZIG_CMD", "zig/zig")

ALL_DRIVERS = [
    "zig", "java", "rust", "python",
]

def run_command(cmd, env=None, check=True, cwd=None):
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, env=env, check=check, cwd=cwd)

def parse_args():
    parser = argparse.ArgumentParser(description="Run TigerBeetle Vortex test.")
    parser.add_argument(
        "--test-duration-seconds",
        type=int,
        help="Duration of the test in seconds.",
    )
    parser.add_argument(
        "--output-directory",
        type=str,
        help="Directory to write test output to.",
    )
    parser.add_argument(
        "--disable-faults",
        action="store_true",
        help="Don't inject network faults.",
    )
    parser.add_argument(
        "--enable-faults",
        action="store_true",
        help="Inject network faults.",
    )
    parser.add_argument(
        "--driver-command",
        type=str,
        help="Command to start the workload driver.",
    )
    parser.add_argument(
        "--replica-count",
        type=int,
        help="Number of replicas.",
    )

    # Script-specific arguments
    parser.add_argument(
        "--driver",
        choices=ALL_DRIVERS,
        type=str,
        help="Build and run a specific driver.",
    )

    parser.add_argument(
        "--all-drivers",
        action="store_true",
        help="Build and run all drivers in turn.",
    )

    return parser.parse_args()

def main():
    if platform.system().lower() != "linux":
        print("❌ This script must be run on Linux.")
        #sys.exit(1)

    args = parse_args()

    if args.all_drivers:
        for driver in ALL_DRIVERS:
            print(f"🌪️  Running vortex with driver: {driver}.")
            args.driver = driver
            run(args)
    else:
        run(args)

def run(args):
    # Reconstruct CLI args to forward
    default_args = []
    forwarded_args = []
    out_directory = None
    if args.test_duration_seconds:
        forwarded_args.append(f"--test-duration-seconds={args.test_duration_seconds}")
    else:
        default_args.append(f"--test-duration-seconds={DEFAULT_TEST_DURATION_SECONDS}");
    if args.output_directory:
        out_directory = args.output_directory
        forwarded_args.append(f"--output-directory={args.output_directory}")
    else:
        out_directory = DEFAULT_OUT_DIRECTORY
        default_args.append(f"--output-directory={DEFAULT_OUT_DIRECTORY}");
    if args.disable_faults:
        forwarded_args.append(f"--disable-faults")
    elif args.enable_faults:
        pass
    elif DEFAULT_DISABLE_FAULTS:
        default_args.append(f"--disable-faults")
    if args.driver_command:
        forwarded_args.append(f"--driver-command={args.driver_command}")
    if args.replica_count:
        forwarded_args.append(f"--replica-count={args.replica_count}")
    else:
        default_args.append(f"--replica-count={DEFAULT_REPLICA_COUNT}");

    # Clean up output directory
    if os.path.exists(out_directory):
        for file in os.listdir(out_directory):
            file_path = os.path.join(out_directory, file)
            if os.path.isfile(file_path):
                os.remove(file_path)
        os.rmdir(out_directory)
    os.makedirs(out_directory, exist_ok=True)

    # Build TigerBeetle
    try:
        run_command([ZIG_CMD, "build", "--verbose"])
        run_command([ZIG_CMD, "build", "vortex:build", "--verbose"])
    except subprocess.CalledProcessError as e:
        print(f"❌ Build failed: {e}")
        sys.exit(e.returncode)

    # Build driver
    build_driver(args.driver)

    # Run vortex
    vortex_path = Path(shutil.which("zig-out/bin/vortex"))
    tigerbeetle_path = Path(shutil.which("zig-out/bin/tigerbeetle"))

    if not vortex_path.exists():
        print(f"❌ Vortex executable not found at {vortex_path}")
        sys.exit(1)
    if not tigerbeetle_path.exists():
        print(f"❌ TigerBeetle executable not found at {tigerbeetle_path}")
        sys.exit(1)

    driver_args = make_driver_args(args.driver)
    driver_env = make_driver_env(args.driver)

    env = os.environ.copy()
    for (key, val) in driver_env:
        env[key] = val

    args = [
        str(vortex_path),
        "supervisor",
        f"--tigerbeetle-executable={tigerbeetle_path}",
    ]
    args += [
        *default_args,
    ]
    args += [
        *forwarded_args,
    ]
    args += [
        *driver_args,
    ]

    try:
        run_command(args, env=env)
    except subprocess.CalledProcessError as e:
        print("❌ vortex supervisor failed.")
        sys.exit(e.returncode)

def build_driver(driver_name: str):
    if driver_name == "java":
        try:
            run_command([ZIG_CMD, "build", "vortex:java"])
        except subprocess.CalledProcessError as e:
            print(f"❌ Build failed: {e}")
            sys.exit(e.returncode)

    if driver_name == "rust":
        try:
            run_command([ZIG_CMD, "build", "vortex:rust"])
        except subprocess.CalledProcessError as e:
            print(f"❌ Build failed: {e}")
            sys.exit(e.returncode)

    if driver_name == "python":
        try:
            run_command([ZIG_CMD, "build", "vortex:python"])
        except subprocess.CalledProcessError as e:
            print(f"❌ Build failed: {e}")
            sys.exit(e.returncode)

def make_driver_args(driver_name: str) -> list[str]:
    if driver_name == "java":
        class_path = "src/clients/java/target/tigerbeetle-java-0.0.1-SNAPSHOT.jar"
        class_path = f"{class_path}:src/testing/vortex/java_driver/target/vortex-driver-java-0.0.1-SNAPSHOT.jar"
        command = f"java -cp {class_path} Main"
        return [f"--driver-command={command}"]
    elif driver_name == "rust":
        command = "src/testing/vortex/rust_driver/target/debug/vortex-driver-rust"
        return [f"--driver-command={command}"]
    elif driver_name == "python":
        command = "src/testing/vortex/python_driver/main.py"
        return [f"--driver-command={command}"]
    else:
        return []

def make_driver_env(driver_name: str) -> list[tuple[str, str]]:
    if driver_name == "python":
        cwd=os.getcwd()
        pythonpath=os.environ.get("PYTHONPATH", "")
        pythonpath=f"{cwd}/src/clients/python/src:{pythonpath}"
        return [("PYTHONPATH", pythonpath)]
    else:
        return []

if __name__ == "__main__":
    main()
