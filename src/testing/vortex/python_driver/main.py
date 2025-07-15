#!/usr/bin/env python3

import sys
import struct
import asyncio
import ctypes
from typing import Optional, List, Union
import tigerbeetle as tb
from tigerbeetle.bindings import CAccount, CTransfer

# Operation constants from src/state_machine.zig
CREATE_ACCOUNTS = 138
CREATE_TRANSFERS = 139
LOOKUP_ACCOUNTS = 140
LOOKUP_TRANSFERS = 141

class BinaryProtocol:
    """Handles the vortex binary protocol over stdin/stdout"""

    def __init__(self, input_stream=None, output_stream=None):
        self.input_stream = input_stream or sys.stdin.buffer
        self.output_stream = output_stream or sys.stdout.buffer

    def read_exact(self, size: int) -> bytes:
        """Read exactly size bytes from input"""
        data = b''
        while len(data) < size:
            chunk = self.input_stream.read(size - len(data))
            if not chunk:
                raise EOFError("Unexpected end of stream")
            data += chunk
        return data

    def receive_operation(self) -> Optional[tuple[int, int, bytes]]:
        """Receive operation, count, and event data"""
        try:
            # Read operation (1 byte) + count (4 bytes)
            header = self.read_exact(5)
            operation = struct.unpack('<B', header[:1])[0]
            count = struct.unpack('<I', header[1:5])[0]

            # Calculate event size based on operation
            event_size = self.get_event_size(operation)

            # Read event data
            event_data = self.read_exact(event_size * count)

            return operation, count, event_data
        except EOFError:
            return None

    def send_results(self, results: List[bytes]):
        """Send result count and result data"""
        # Write result count (4 bytes)
        self.output_stream.write(struct.pack('<I', len(results)))

        # Write result data
        for result in results:
            self.output_stream.write(result)

        self.output_stream.flush()

    def get_event_size(self, operation: int) -> int:
        """Get event size in bytes for each operation"""
        if operation in [CREATE_ACCOUNTS, CREATE_TRANSFERS]:
            return 128
        elif operation in [LOOKUP_ACCOUNTS, LOOKUP_TRANSFERS]:
            return 16
        else:
            raise ValueError(f"Unsupported operation: {operation}")

    def get_result_size(self, operation: int) -> int:
        """Get result size in bytes for each operation"""
        if operation in [CREATE_ACCOUNTS, CREATE_TRANSFERS]:
            return 8
        elif operation in [LOOKUP_ACCOUNTS, LOOKUP_TRANSFERS]:
            return 128
        else:
            raise ValueError(f"Unsupported operation: {operation}")

class VortexDriver:
    """Main driver class that handles TigerBeetle operations"""

    def __init__(self, cluster_id: int, replica_addresses: str):
        self.client = tb.ClientSync(cluster_id, replica_addresses)
        self.protocol = BinaryProtocol()

    def run(self):
        """Main event loop"""
        while True:
            try:
                operation_data = self.protocol.receive_operation()
                if operation_data is None:
                    break

                operation, count, event_data = operation_data

                # Validate input data
                if count < 0:
                    print(f"Error: invalid count {count}", file=sys.stderr)
                    break

                expected_size = self.protocol.get_event_size(operation) * count
                assert len(event_data) == expected_size

                results = self.execute_operation(operation, count, event_data)
                try:
                    self.protocol.send_results(results)
                except BrokenPipeError:
                    # Workload generator might disappear
                    pass

            except EOFError:
                # Normal termination
                break
            except Exception as e:
                print(f"Error in driver loop: {e}", file=sys.stderr)
                break

    def execute_operation(self, operation: int, count: int, event_data: bytes) -> List[bytes]:
        """Execute a TigerBeetle operation and return results"""
        if operation == CREATE_ACCOUNTS:
            return self.create_accounts(count, event_data)
        elif operation == CREATE_TRANSFERS:
            return self.create_transfers(count, event_data)
        elif operation == LOOKUP_ACCOUNTS:
            return self.lookup_accounts(count, event_data)
        elif operation == LOOKUP_TRANSFERS:
            return self.lookup_transfers(count, event_data)
        else:
            raise ValueError(f"Unsupported operation: {operation}")

    def create_accounts(self, count: int, event_data: bytes) -> List[bytes]:
        """Handle create_accounts operation"""
        accounts = []
        for i in range(count):
            offset = i * 128
            account_bytes = event_data[offset:offset + 128]

            # Use CAccount structure to deserialize the binary data
            c_account = CAccount()
            ctypes.memmove(ctypes.addressof(c_account), account_bytes, 128)

            # Convert to Python Account object
            account = c_account.to_python()
            accounts.append(account)

        # Execute create_accounts
        results = self.client.create_accounts(accounts)

        # Convert results to binary format
        binary_results = []
        for result in results:
            # Each result is 8 bytes: index (4 bytes) + result enum (4 bytes)
            binary_result = struct.pack('<II', result.index, result.result.value)
            binary_results.append(binary_result)

        return binary_results

    def create_transfers(self, count: int, event_data: bytes) -> List[bytes]:
        """Handle create_transfers operation"""
        transfers = []
        for i in range(count):
            offset = i * 128
            transfer_bytes = event_data[offset:offset + 128]

            # Use CTransfer structure to deserialize the binary data
            c_transfer = CTransfer()
            ctypes.memmove(ctypes.addressof(c_transfer), transfer_bytes, 128)

            # Convert to Python Transfer object
            transfer = c_transfer.to_python()
            transfers.append(transfer)

        # Execute create_transfers
        results = self.client.create_transfers(transfers)

        # Convert results to binary format
        binary_results = []
        for result in results:
            binary_result = struct.pack('<II', result.index, result.result.value)
            binary_results.append(binary_result)

        return binary_results

    def lookup_accounts(self, count: int, event_data: bytes) -> List[bytes]:
        """Handle lookup_accounts operation"""
        account_ids = []
        for i in range(count):
            offset = i * 16
            id_bytes = event_data[offset:offset + 16]
            account_id = struct.unpack('<QQ', id_bytes)
            account_id = account_id[0] + (account_id[1] << 64)
            account_ids.append(account_id)

        # Execute lookup_accounts
        accounts = self.client.lookup_accounts(account_ids)

        # Convert accounts to binary format using CAccount structure
        binary_results = []
        for account in accounts:
            c_account = CAccount.from_param(account)
            account_bytes = ctypes.string_at(ctypes.addressof(c_account), 128)
            binary_results.append(account_bytes)

        return binary_results

    def lookup_transfers(self, count: int, event_data: bytes) -> List[bytes]:
        """Handle lookup_transfers operation"""
        transfer_ids = []
        for i in range(count):
            offset = i * 16
            id_bytes = event_data[offset:offset + 16]
            transfer_id = struct.unpack('<QQ', id_bytes)
            transfer_id = transfer_id[0] + (transfer_id[1] << 64)
            transfer_ids.append(transfer_id)

        # Execute lookup_transfers
        transfers = self.client.lookup_transfers(transfer_ids)

        # Convert transfers to binary format using CTransfer structure
        binary_results = []
        for transfer in transfers:
            c_transfer = CTransfer.from_param(transfer)
            transfer_bytes = ctypes.string_at(ctypes.addressof(c_transfer), 128)
            binary_results.append(transfer_bytes)

        return binary_results

def main():
    if len(sys.argv) != 3:
        print("Usage: python main.py <cluster_id> <replica_addresses>", file=sys.stderr)
        sys.exit(1)

    cluster_id = int(sys.argv[1])
    replica_addresses = sys.argv[2]

    driver = VortexDriver(cluster_id, replica_addresses)
    driver.run()

if __name__ == "__main__":
    main()
