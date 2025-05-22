#!/usr/bin/env python3

import os
import platform
import subprocess
import sys
from pathlib import Path
import argparse

DEFAULT_OUT_DIR = "./vortex-out"
DEFAULT_TEST_DURATION_SECONDS = 10
DEFAULT_REPLICA_COUNT = 1

ZIG_CMD = os.environ.get("ZIG_CMD", "zig/zig")

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
        choices=["zig", "java", "rust"],
        type=str,
        help="Command to start the workload driver.",
    )

    return parser.parse_args()

def main():
    if platform.system().lower() != "linux":
        print("❌ This script must be run on Linux.")
        sys.exit(1)

    args = parse_args()

    # Reconstruct CLI args to forward
    forwarded_args = []
    if args.test_duration_seconds:
        forwarded_args.append(f"--test-duration-seconds={args.test_duration_seconds}")
    if args.output_directory:
        forwarded_args.append(f"--output-directory={args.output_directory}")
    if args.disable_faults:
        forwarded_args.append(f"--disable-faults")
    if args.driver_command:
        forwarded_args.append(f"--driver-command={args.driver_command}")
    if args.replica_count:
        forwarded_args.append(f"--replica-count={args.replica_count}")

    use_default_test_duration = True if not args.test_duration_seconds else False
    use_default_out_dir = True if not args.output_directory else False
    use_default_replica_count = True if not args.replica_count else False

    # Build TigerBeetle
    try:
        run_command([ZIG_CMD, "build"])
        run_command([ZIG_CMD, "build", "vortex"])
    except subprocess.CalledProcessError as e:
        print(f"❌ Build failed: {e}")
        sys.exit(e.returncode)

    # Build driver
    build_driver(args.driver)

    # Run vortex
    vortex_path = Path("zig-out/bin/vortex")
    tigerbeetle_path = Path("zig-out/bin/tigerbeetle")

    if not vortex_path.exists():
        print(f"❌ Vortex executable not found at {vortex_path}")
        sys.exit(1)
    if not tigerbeetle_path.exists():
        print(f"❌ TigerBeetle executable not found at {tigerbeetle_path}")
        sys.exit(1)

    driver_args = make_driver_args(args.driver)

    args = [
        str(vortex_path),
        "run",
        f"--tigerbeetle-executable={tigerbeetle_path}",
    ]
    args += [ f"--test-duration-seconds={DEFAULT_TEST_DURATION_SECONDS}" ] if use_default_test_duration else []
    args += [ f"--output-directory={DEFAULT_OUT_DIR}" ] if use_default_out_dir else []
    args += [ f"--replica-count={DEFAULT_REPLICA_COUNT}" ] if use_default_replica_count else []
    args += [
        *forwarded_args,
    ]
    args += [
        *driver_args,
    ]

    try:
        run_command(args)
    except subprocess.CalledProcessError as e:
        print("❌ vortex supervisor failed.")
        sys.exit(e.returncode)

def build_driver(driver_name: str):
    if driver_name == "java":
        try:
            run_command(
                ["mvn", "install", "-DskipTests"],
                cwd="./src/clients/java",
            )
            run_command(
                ["mvn", "package", "-DskipTests"],
                cwd="./src/testing/vortex/java_driver",
            )
        except subprocess.CalledProcessError as e:
            print(f"❌ Build failed: {e}")
            sys.exit(e.returncode)

    if driver_name == "rust":
        try:
            run_command(
                ["cargo", "build"],
                cwd="./src/testing/vortex/rust_driver",
            )
        except subprocess.CalledProcessError as e:
            print(f"❌ Build failed: {e}")
            sys.exit(e.returncode)

def make_driver_args(driver_name: str) -> [str]:
    if driver_name == "java":
        class_path = "src/clients/java/target/tigerbeetle-java-0.0.1-SNAPSHOT.jar"
        class_path = f"{class_path}:src/testing/vortex/java_driver/target/driver-0.0.1-SNAPSHOT.jar"
        command = f"java -cp {class_path} Main"
        return [f"--driver-command={command}"]
    elif driver_name == "rust":
        command = "src/testing/vortex/rust_driver/target/debug/vortex-driver-rust"
        return [f"--driver-command={command}"]
    else:
        return []

if __name__ == "__main__":
    main()
