#!/usr/bin/env python3

import sys
import struct
import asyncio
import ctypes
from typing import Optional, List, Union
from enum import Enum
import tigerbeetle as tb
from tigerbeetle.bindings import CAccount, CTransfer

# Operation constants from src/state_machine.zig
CREATE_ACCOUNTS = 138
CREATE_TRANSFERS = 139
LOOKUP_ACCOUNTS = 140
LOOKUP_TRANSFERS = 141

class Request:
    pass

class CreateAccountsRequest(Request):
    def __init__(self, accounts: List[tb.Account]):
        self.accounts = accounts

class CreateTransfersRequest(Request):
    def __init__(self, transfers: List[tb.Transfer]):
        self.transfers = transfers

class LookupAccountsRequest(Request):
    def __init__(self, account_ids: List[int]):
        self.account_ids = account_ids

class LookupTransfersRequest(Request):
    def __init__(self, transfer_ids: List[int]):
        self.transfer_ids = transfer_ids

class Reply:
    pass

class CreateAccountsReply(Reply):
    def __init__(self, results: List[tb.CreateAccountsResult]):
        self.results = results

class CreateTransfersReply(Reply):
    def __init__(self, results: List[tb.CreateTransfersResult]):
        self.results = results

class LookupAccountsReply(Reply):
    def __init__(self, accounts: List[tb.Account]):
        self.accounts = accounts

class LookupTransfersReply(Reply):
    def __init__(self, transfers: List[tb.Transfer]):
        self.transfers = transfers

class BinaryProtocol:
    def __init__(self, input_stream=None, output_stream=None):
        self.input_stream = input_stream or sys.stdin.buffer
        self.output_stream = output_stream or sys.stdout.buffer

    def read_exact(self, size: int) -> bytes:
        data = b''
        while len(data) < size:
            chunk = self.input_stream.read(size - len(data))
            if not chunk:
                raise EOFError("Unexpected end of stream")
            data += chunk
        return data

    def receive(self) -> Optional[Request]:
        """Receive operation and return typed Request object"""
        try:
            # Read operation (1 byte) + count (4 bytes)
            header = self.read_exact(5)
            operation = struct.unpack('<B', header[:1])[0]
            count = struct.unpack('<I', header[1:5])[0]

            if operation == CREATE_ACCOUNTS:
                accounts = []
                for i in range(count):
                    account_bytes = self.read_exact(128)
                    c_account = CAccount()
                    ctypes.memmove(ctypes.addressof(c_account), account_bytes, 128)
                    account = c_account.to_python()
                    accounts.append(account)
                return CreateAccountsRequest(accounts)

            elif operation == CREATE_TRANSFERS:
                transfers = []
                for i in range(count):
                    transfer_bytes = self.read_exact(128)
                    c_transfer = CTransfer()
                    ctypes.memmove(ctypes.addressof(c_transfer), transfer_bytes, 128)
                    transfer = c_transfer.to_python()
                    transfers.append(transfer)
                return CreateTransfersRequest(transfers)

            elif operation == LOOKUP_ACCOUNTS:
                account_ids = []
                for i in range(count):
                    id_bytes = self.read_exact(16)
                    account_id = struct.unpack('<QQ', id_bytes)
                    account_id = account_id[0] + (account_id[1] << 64)
                    account_ids.append(account_id)
                return LookupAccountsRequest(account_ids)

            elif operation == LOOKUP_TRANSFERS:
                transfer_ids = []
                for i in range(count):
                    id_bytes = self.read_exact(16)
                    transfer_id = struct.unpack('<QQ', id_bytes)
                    transfer_id = transfer_id[0] + (transfer_id[1] << 64)
                    transfer_ids.append(transfer_id)
                return LookupTransfersRequest(transfer_ids)

            else:
                raise ValueError(f"Unsupported operation: {operation}")

        except EOFError:
            return None

    def send_reply(self, reply: Reply):
        """Send typed Reply object as binary data"""
        if isinstance(reply, CreateAccountsReply):
            self.output_stream.write(struct.pack('<I', len(reply.results)))
            for result in reply.results:
                binary_result = struct.pack('<II', result.index, result.result.value)
                self.output_stream.write(binary_result)

        elif isinstance(reply, CreateTransfersReply):
            self.output_stream.write(struct.pack('<I', len(reply.results)))
            for result in reply.results:
                binary_result = struct.pack('<II', result.index, result.result.value)
                self.output_stream.write(binary_result)

        elif isinstance(reply, LookupAccountsReply):
            self.output_stream.write(struct.pack('<I', len(reply.accounts)))
            for account in reply.accounts:
                c_account = CAccount.from_param(account)
                account_bytes = ctypes.string_at(ctypes.addressof(c_account), 128)
                self.output_stream.write(account_bytes)

        elif isinstance(reply, LookupTransfersReply):
            self.output_stream.write(struct.pack('<I', len(reply.transfers)))
            for transfer in reply.transfers:
                c_transfer = CTransfer.from_param(transfer)
                transfer_bytes = ctypes.string_at(ctypes.addressof(c_transfer), 128)
                self.output_stream.write(transfer_bytes)

        else:
            raise ValueError(f"Unsupported reply type: {type(reply)}")

        self.output_stream.flush()


class VortexDriver:
    def __init__(self, cluster_id: int, replica_addresses: str):
        self.client = tb.ClientSync(cluster_id, replica_addresses)
        self.protocol = BinaryProtocol()

    def run(self):
        while True:
            try:
                request = self.protocol.receive()
                if request is None:
                    break

                reply = self.execute_request(request)
                try:
                    self.protocol.send_reply(reply)
                except BrokenPipeError:
                    # Workload generator might disappear
                    pass

            except EOFError:
                # Normal termination
                break
            except Exception as e:
                print(f"Error in driver loop: {e}", file=sys.stderr)
                break

    def execute_request(self, request: Request) -> Reply:
        if isinstance(request, CreateAccountsRequest):
            return self.create_accounts(request.accounts)
        elif isinstance(request, CreateTransfersRequest):
            return self.create_transfers(request.transfers)
        elif isinstance(request, LookupAccountsRequest):
            return self.lookup_accounts(request.account_ids)
        elif isinstance(request, LookupTransfersRequest):
            return self.lookup_transfers(request.transfer_ids)
        else:
            raise ValueError(f"Unsupported request type: {type(request)}")

    def create_accounts(self, accounts: List[tb.Account]) -> CreateAccountsReply:
        results = self.client.create_accounts(accounts)
        return CreateAccountsReply(results)

    def create_transfers(self, transfers: List[tb.Transfer]) -> CreateTransfersReply:
        results = self.client.create_transfers(transfers)
        return CreateTransfersReply(results)

    def lookup_accounts(self, account_ids: List[int]) -> LookupAccountsReply:
        accounts = self.client.lookup_accounts(account_ids)
        return LookupAccountsReply(accounts)

    def lookup_transfers(self, transfer_ids: List[int]) -> LookupTransfersReply:
        transfers = self.client.lookup_transfers(transfer_ids)
        return LookupTransfersReply(transfers)

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
