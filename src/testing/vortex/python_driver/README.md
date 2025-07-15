# Python Vortex Driver

A Python implementation of the TigerBeetle vortex driver for end-to-end testing.

## Setup

```bash
pip install -r requirements.txt
```

## Usage

```bash
python main.py <cluster_id> <replica_addresses>
```

Where:
- `cluster_id`: The cluster ID as a string representation of u128
- `replica_addresses`: Comma-separated list of replica addresses

## Protocol

This driver implements the vortex binary protocol over stdin/stdout for communication with the workload generator.