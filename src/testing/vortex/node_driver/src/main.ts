// Node.js Vortex Driver for TigerBeetle
import { createClient, Account, Transfer, Operation } from 'tigerbeetle-node';

// Operation constants from src/state_machine.zig
const CREATE_ACCOUNTS = 138;
const CREATE_TRANSFERS = 139;
const LOOKUP_ACCOUNTS = 140;
const LOOKUP_TRANSFERS = 141;

class BinaryProtocol {
    private stdin: NodeJS.ReadStream;
    private stdout: NodeJS.WriteStream;

    constructor() {
        this.stdin = process.stdin;
        this.stdout = process.stdout;
    }

    async readExact(size: number): Promise<Buffer> {
        let data = Buffer.alloc(0);

        return new Promise((resolve, reject) => {
            const onData = (chunk: Buffer) => {
                data = Buffer.concat([data, chunk]);

                if (data.length >= size) {
                    this.stdin.removeListener('data', onData);
                    this.stdin.removeListener('end', onEnd);
                    this.stdin.removeListener('error', onError);

                    const result = data.subarray(0, size);
                    // Put back any extra data
                    if (data.length > size) {
                        this.stdin.unshift(data.subarray(size));
                    }
                    resolve(result);
                }
            };

            const onEnd = () => {
                this.stdin.removeListener('data', onData);
                this.stdin.removeListener('error', onError);
                reject(new Error('Unexpected end of stream'));
            };

            const onError = (err: Error) => {
                this.stdin.removeListener('data', onData);
                this.stdin.removeListener('end', onEnd);
                reject(err);
            };

            this.stdin.on('data', onData);
            this.stdin.on('end', onEnd);
            this.stdin.on('error', onError);
        });
    }

    async receiveOperation(): Promise<{operation: number, count: number, data: Buffer} | null> {
        try {
            // Read operation (1 byte) + count (4 bytes)
            const header = await this.readExact(5);
            const operation = header.readUInt8(0);
            const count = header.readUInt32LE(1);

            // Calculate event size based on operation
            const eventSize = this.getEventSize(operation);

            // Read event data
            const eventData = await this.readExact(eventSize * count);

            return { operation, count, data: eventData };
        } catch (error) {
            if (error instanceof Error && error.message === 'Unexpected end of stream') {
                return null;
            }
            throw error;
        }
    }

    sendResults(results: Buffer[]): void {
        // Write result count (4 bytes)
        const countBuffer = Buffer.allocUnsafe(4);
        countBuffer.writeUInt32LE(results.length, 0);
        this.stdout.write(countBuffer);

        // Write result data
        for (const result of results) {
            this.stdout.write(result);
        }
    }

    private getEventSize(operation: number): number {
        if (operation === CREATE_ACCOUNTS || operation === CREATE_TRANSFERS) {
            return 128;
        } else if (operation === LOOKUP_ACCOUNTS || operation === LOOKUP_TRANSFERS) {
            return 16;
        } else {
            throw new Error(`Unsupported operation: ${operation}`);
        }
    }
}

class VortexDriver {
    private client: any;
    private protocol: BinaryProtocol;

    constructor(clusterId: bigint, replicaAddresses: string[]) {
        this.client = createClient({
            cluster_id: clusterId,
            replica_addresses: replicaAddresses
        });
        this.protocol = new BinaryProtocol();
    }

    async run(): Promise<void> {
        while (true) {
            try {
                const operationData = await this.protocol.receiveOperation();
                if (operationData === null) {
                    break;
                }

                const { operation, count, data } = operationData;

                // Validate input data
                if (count < 0) {
                    console.error(`Error: invalid count ${count}`);
                    break;
                }

                const expectedSize = this.getEventSize(operation) * count;
                if (data.length !== expectedSize) {
                    console.error(`Error: expected ${expectedSize} bytes, got ${data.length}`);
                    break;
                }

                const results = await this.executeOperation(operation, count, data);
                this.protocol.sendResults(results);

            } catch (error) {
                if (error instanceof Error && error.message === 'Unexpected end of stream') {
                    break;
                }
                console.error(`Error in driver loop: ${error}`);
                break;
            }
        }
    }

    private async executeOperation(operation: number, count: number, data: Buffer): Promise<Buffer[]> {
        switch (operation) {
            case CREATE_ACCOUNTS:
                return this.createAccounts(count, data);
            case CREATE_TRANSFERS:
                return this.createTransfers(count, data);
            case LOOKUP_ACCOUNTS:
                return this.lookupAccounts(count, data);
            case LOOKUP_TRANSFERS:
                return this.lookupTransfers(count, data);
            default:
                throw new Error(`Unsupported operation: ${operation}`);
        }
    }

    private getEventSize(operation: number): number {
        if (operation === CREATE_ACCOUNTS || operation === CREATE_TRANSFERS) {
            return 128;
        } else if (operation === LOOKUP_ACCOUNTS || operation === LOOKUP_TRANSFERS) {
            return 16;
        } else {
            throw new Error(`Unsupported operation: ${operation}`);
        }
    }

    private async createAccounts(count: number, data: Buffer): Promise<Buffer[]> {
        const accounts: Account[] = [];
        for (let i = 0; i < count; i++) {
            const offset = i * 128;
            const accountBuffer = data.subarray(offset, offset + 128);
            const account = this.parseAccount(accountBuffer);
            accounts.push(account);
        }

        const results = await this.client.createAccounts(accounts);

        // Convert results to binary format
        const binaryResults: Buffer[] = [];
        for (const result of results) {
            const buffer = Buffer.allocUnsafe(8);
            buffer.writeUInt32LE(result.index, 0);
            buffer.writeUInt32LE(result.result, 4);
            binaryResults.push(buffer);
        }

        return binaryResults;
    }

    private async createTransfers(count: number, data: Buffer): Promise<Buffer[]> {
        const transfers: Transfer[] = [];
        for (let i = 0; i < count; i++) {
            const offset = i * 128;
            const transferBuffer = data.subarray(offset, offset + 128);
            const transfer = this.parseTransfer(transferBuffer);
            transfers.push(transfer);
        }

        const results = await this.client.createTransfers(transfers);

        // Convert results to binary format
        const binaryResults: Buffer[] = [];
        for (const result of results) {
            const buffer = Buffer.allocUnsafe(8);
            buffer.writeUInt32LE(result.index, 0);
            buffer.writeUInt32LE(result.result, 4);
            binaryResults.push(buffer);
        }

        return binaryResults;
    }

    private async lookupAccounts(count: number, data: Buffer): Promise<Buffer[]> {
        const accountIds: bigint[] = [];
        for (let i = 0; i < count; i++) {
            const offset = i * 16;
            const idBuffer = data.subarray(offset, offset + 16);
            const id = this.parseU128(idBuffer);
            accountIds.push(id);
        }

        const accounts = await this.client.lookupAccounts(accountIds);

        // Convert accounts to binary format
        const binaryResults: Buffer[] = [];
        for (const account of accounts) {
            const buffer = this.serializeAccount(account);
            binaryResults.push(buffer);
        }

        return binaryResults;
    }

    private async lookupTransfers(count: number, data: Buffer): Promise<Buffer[]> {
        const transferIds: bigint[] = [];
        for (let i = 0; i < count; i++) {
            const offset = i * 16;
            const idBuffer = data.subarray(offset, offset + 16);
            const id = this.parseU128(idBuffer);
            transferIds.push(id);
        }

        const transfers = await this.client.lookupTransfers(transferIds);

        // Convert transfers to binary format
        const binaryResults: Buffer[] = [];
        for (const transfer of transfers) {
            const buffer = this.serializeTransfer(transfer);
            binaryResults.push(buffer);
        }

        return binaryResults;
    }

    private parseU128(buffer: Buffer): bigint {
        // Read as two 64-bit values in little-endian format
        const lo = buffer.readBigUInt64LE(0);
        const hi = buffer.readBigUInt64LE(8);
        return lo + (hi << 64n);
    }

    private serializeU128(value: bigint): Buffer {
        const buffer = Buffer.allocUnsafe(16);
        // Write as two 64-bit values in little-endian format
        buffer.writeBigUInt64LE(value & 0xFFFFFFFFFFFFFFFFn, 0);
        buffer.writeBigUInt64LE(value >> 64n, 8);
        return buffer;
    }

    private parseAccount(buffer: Buffer): Account {
        return {
            id: this.parseU128(buffer.subarray(0, 16)),
            debits_pending: this.parseU128(buffer.subarray(16, 32)),
            debits_posted: this.parseU128(buffer.subarray(32, 48)),
            credits_pending: this.parseU128(buffer.subarray(48, 64)),
            credits_posted: this.parseU128(buffer.subarray(64, 80)),
            user_data_128: this.parseU128(buffer.subarray(80, 96)),
            user_data_64: buffer.readBigUInt64LE(96),
            user_data_32: buffer.readUInt32LE(104),
            reserved: buffer.readUInt32LE(108),
            ledger: buffer.readUInt32LE(112),
            code: buffer.readUInt16LE(116),
            flags: buffer.readUInt16LE(118),
            timestamp: buffer.readBigUInt64LE(120)
        };
    }

    private parseTransfer(buffer: Buffer): Transfer {
        return {
            id: this.parseU128(buffer.subarray(0, 16)),
            debit_account_id: this.parseU128(buffer.subarray(16, 32)),
            credit_account_id: this.parseU128(buffer.subarray(32, 48)),
            amount: this.parseU128(buffer.subarray(48, 64)),
            pending_id: this.parseU128(buffer.subarray(64, 80)),
            user_data_128: this.parseU128(buffer.subarray(80, 96)),
            user_data_64: buffer.readBigUInt64LE(96),
            user_data_32: buffer.readUInt32LE(104),
            timeout: buffer.readUInt32LE(108),
            ledger: buffer.readUInt32LE(112),
            code: buffer.readUInt16LE(116),
            flags: buffer.readUInt16LE(118),
            timestamp: buffer.readBigUInt64LE(120)
        };
    }

    private serializeAccount(account: Account): Buffer {
        const buffer = Buffer.allocUnsafe(128);

        this.serializeU128(account.id).copy(buffer, 0);
        this.serializeU128(account.debits_pending).copy(buffer, 16);
        this.serializeU128(account.debits_posted).copy(buffer, 32);
        this.serializeU128(account.credits_pending).copy(buffer, 48);
        this.serializeU128(account.credits_posted).copy(buffer, 64);
        this.serializeU128(account.user_data_128).copy(buffer, 80);
        buffer.writeBigUInt64LE(account.user_data_64, 96);
        buffer.writeUInt32LE(account.user_data_32, 104);
        buffer.writeUInt32LE(account.reserved, 108);
        buffer.writeUInt32LE(account.ledger, 112);
        buffer.writeUInt16LE(account.code, 116);
        buffer.writeUInt16LE(account.flags, 118);
        buffer.writeBigUInt64LE(account.timestamp, 120);

        return buffer;
    }

    private serializeTransfer(transfer: Transfer): Buffer {
        const buffer = Buffer.allocUnsafe(128);

        this.serializeU128(transfer.id).copy(buffer, 0);
        this.serializeU128(transfer.debit_account_id).copy(buffer, 16);
        this.serializeU128(transfer.credit_account_id).copy(buffer, 32);
        this.serializeU128(transfer.amount).copy(buffer, 48);
        this.serializeU128(transfer.pending_id).copy(buffer, 64);
        this.serializeU128(transfer.user_data_128).copy(buffer, 80);
        buffer.writeBigUInt64LE(transfer.user_data_64, 96);
        buffer.writeUInt32LE(transfer.user_data_32, 104);
        buffer.writeUInt32LE(transfer.timeout, 108);
        buffer.writeUInt32LE(transfer.ledger, 112);
        buffer.writeUInt16LE(transfer.code, 116);
        buffer.writeUInt16LE(transfer.flags, 118);
        buffer.writeBigUInt64LE(transfer.timestamp, 120);

        return buffer;
    }
}

function main() {
    if (process.argv.length !== 4) {
        console.error("Usage: node main.js <cluster_id> <replica_addresses>");
        process.exit(1);
    }

    const clusterId = BigInt(process.argv[2]);
    const replicaAddresses = process.argv[3].split(',');

    const driver = new VortexDriver(clusterId, replicaAddresses);
    driver.run().catch(err => {
        console.error("Error:", err);
        process.exit(1);
    });
}

if (require.main === module) {
    main();
}
