# Node.js Vortex Driver

This directory contains the Node.js vortex driver for TigerBeetle testing.

## Building

```bash
npm install
npm run build
```

## Running

```bash
node dist/main.js <cluster_id> <replica_addresses>
```

## Integration

The driver is integrated into the vortex testing framework and can be run using:

```bash
./run-vortex.py --driver node
```