# frozen_string_literal: true

require_relative "ffi"

module TigerBeetle
  class Client
    class InitError < StandardError; end
    class SubmitError < StandardError; end

    def initialize(cluster_id, addresses)
      @handle = FFI::ClientHandle.new
      @inflight = {}
      @inflight_mutex = Mutex.new
      @packet_counter = 0

      # Must keep callback reference alive to prevent GC
      @callback = method(:on_completion)

      cluster_ptr = uint128_ptr(cluster_id)
      status = FFI.tb_client_init(
        @handle,
        cluster_ptr,
        addresses,
        addresses.bytesize,
        0, # completion_ctx unused - we use packet.user_data
        @callback
      )

      raise InitError, "tb_client_init failed: #{status}" unless status == :SUCCESS
    end

    def close
      FFI.tb_client_deinit(@handle)
    end

    # Low-level submit - returns raw result hash
    # result[:status] - PacketStatus
    # result[:timestamp] - server timestamp
    # result[:data] - raw bytes (or nil)
    def submit_raw(operation, data_ptr, data_size)
      queue = Queue.new
      # Allocate zeroed memory for the packet (third arg = clear memory)
      packet_mem = ::FFI::MemoryPointer.new(FFI::Packet.size, 1, true)
      packet = FFI::Packet.new(packet_mem)
      packet_id = next_packet_id

      @inflight_mutex.synchronize { @inflight[packet_id] = queue }

      packet[:user_data] = ::FFI::Pointer.new(packet_id)
      packet[:operation] = FFI::Operation[operation]
      packet[:data] = data_ptr
      packet[:data_size] = data_size
      packet[:user_tag] = 0
      packet[:status] = :OK

      status = FFI.tb_client_submit(@handle, packet)
      unless status == :OK
        @inflight_mutex.synchronize { @inflight.delete(packet_id) }
        raise SubmitError, "tb_client_submit failed: #{status}"
      end

      # Block until callback fires
      result = queue.pop

      @inflight_mutex.synchronize { @inflight.delete(packet_id) }

      result
    end

    # High-level: create accounts
    # Returns array of CreateAccountsResult for failed accounts (empty = all succeeded)
    def create_accounts(accounts)
      accounts = Array(accounts)
      return [] if accounts.empty?

      buffer = allocate_array(FFI::Account, accounts.size)
      accounts.each_with_index do |account, i|
        copy_account_to_buffer(buffer, i, account)
      end

      result = submit_raw(:CREATE_ACCOUNTS, buffer, accounts.size * FFI::Account.size)
      raise SubmitError, "create_accounts failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::CreateAccountsResult)
    end

    # High-level: create transfers
    # Returns array of CreateTransfersResult for failed transfers (empty = all succeeded)
    def create_transfers(transfers)
      transfers = Array(transfers)
      return [] if transfers.empty?

      buffer = allocate_array(FFI::Transfer, transfers.size)
      transfers.each_with_index do |transfer, i|
        copy_transfer_to_buffer(buffer, i, transfer)
      end

      result = submit_raw(:CREATE_TRANSFERS, buffer, transfers.size * FFI::Transfer.size)
      raise SubmitError, "create_transfers failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::CreateTransfersResult)
    end

    # High-level: lookup accounts by ID
    # Returns array of Account
    def lookup_accounts(ids)
      ids = Array(ids)
      return [] if ids.empty?

      buffer = allocate_array(FFI::UINT128, ids.size)
      ids.each_with_index do |id, i|
        write_uint128(buffer + i * FFI::UINT128.size, id)
      end

      result = submit_raw(:LOOKUP_ACCOUNTS, buffer, ids.size * FFI::UINT128.size)
      raise SubmitError, "lookup_accounts failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::Account)
    end

    # High-level: lookup transfers by ID
    # Returns array of Transfer
    def lookup_transfers(ids)
      ids = Array(ids)
      return [] if ids.empty?

      buffer = allocate_array(FFI::UINT128, ids.size)
      ids.each_with_index do |id, i|
        write_uint128(buffer + i * FFI::UINT128.size, id)
      end

      result = submit_raw(:LOOKUP_TRANSFERS, buffer, ids.size * FFI::UINT128.size)
      raise SubmitError, "lookup_transfers failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::Transfer)
    end

    # High-level: get transfers for an account
    # Returns array of Transfer
    def get_account_transfers(filter)
      buffer = allocate_array(FFI::AccountFilter, 1)
      copy_account_filter_to_buffer(buffer, filter)

      result = submit_raw(:GET_ACCOUNT_TRANSFERS, buffer, FFI::AccountFilter.size)
      raise SubmitError, "get_account_transfers failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::Transfer)
    end

    # High-level: get balance history for an account
    # Returns array of AccountBalance
    def get_account_balances(filter)
      buffer = allocate_array(FFI::AccountFilter, 1)
      copy_account_filter_to_buffer(buffer, filter)

      result = submit_raw(:GET_ACCOUNT_BALANCES, buffer, FFI::AccountFilter.size)
      raise SubmitError, "get_account_balances failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::AccountBalance)
    end

    # High-level: query accounts by filter criteria
    # Returns array of Account
    def query_accounts(filter)
      buffer = allocate_array(FFI::QueryFilter, 1)
      copy_query_filter_to_buffer(buffer, filter)

      result = submit_raw(:QUERY_ACCOUNTS, buffer, FFI::QueryFilter.size)
      raise SubmitError, "query_accounts failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::Account)
    end

    # High-level: query transfers by filter criteria
    # Returns array of Transfer
    def query_transfers(filter)
      buffer = allocate_array(FFI::QueryFilter, 1)
      copy_query_filter_to_buffer(buffer, filter)

      result = submit_raw(:QUERY_TRANSFERS, buffer, FFI::QueryFilter.size)
      raise SubmitError, "query_transfers failed: #{result[:status]}" unless result[:status] == :OK

      parse_results(result[:data], FFI::Transfer)
    end

    private

    def on_completion(_ctx, packet, timestamp, result_ptr, result_len)
      # packet is already a Packet struct (via Packet.by_ref in callback signature)
      packet_id = packet[:user_data].address
      status = packet[:status]

      # Copy result data - pointer only valid during callback
      result_data = result_len > 0 ? result_ptr.read_bytes(result_len) : nil

      result = {
        status: status,
        timestamp: timestamp,
        data: result_data
      }

      queue = @inflight_mutex.synchronize { @inflight[packet_id] }
      queue&.push(result)
    end

    def next_packet_id
      @inflight_mutex.synchronize { @packet_counter += 1 }
    end

    def uint128_ptr(value)
      ptr = ::FFI::MemoryPointer.new(:uint8, 16)
      write_uint128(ptr, value)
      ptr
    end

    def write_uint128(ptr, value)
      lo = value & 0xFFFFFFFFFFFFFFFF
      hi = (value >> 64) & 0xFFFFFFFFFFFFFFFF
      ptr.write_array_of_uint64([lo, hi])
    end

    def allocate_array(struct_class, count)
      # Third arg = true to zero-initialize memory (important for reserved fields)
      ::FFI::MemoryPointer.new(struct_class.size, count, true)
    end

    def copy_account_to_buffer(buffer, index, account)
      ptr = buffer + index * FFI::Account.size
      struct = FFI::Account.new(ptr)

      write_uint128(struct[:id].to_ptr, account[:id] || 0)
      write_uint128(struct[:user_data_128].to_ptr, account[:user_data_128] || 0)
      struct[:user_data_64] = account[:user_data_64] || 0
      struct[:user_data_32] = account[:user_data_32] || 0
      struct[:ledger] = account[:ledger] || 0
      struct[:code] = account[:code] || 0
      struct[:flags] = account[:flags] || 0
    end

    def copy_transfer_to_buffer(buffer, index, transfer)
      ptr = buffer + index * FFI::Transfer.size
      struct = FFI::Transfer.new(ptr)

      write_uint128(struct[:id].to_ptr, transfer[:id] || 0)
      write_uint128(struct[:debit_account_id].to_ptr, transfer[:debit_account_id] || 0)
      write_uint128(struct[:credit_account_id].to_ptr, transfer[:credit_account_id] || 0)
      write_uint128(struct[:amount].to_ptr, transfer[:amount] || 0)
      write_uint128(struct[:pending_id].to_ptr, transfer[:pending_id] || 0)
      write_uint128(struct[:user_data_128].to_ptr, transfer[:user_data_128] || 0)
      struct[:user_data_64] = transfer[:user_data_64] || 0
      struct[:user_data_32] = transfer[:user_data_32] || 0
      struct[:timeout] = transfer[:timeout] || 0
      struct[:ledger] = transfer[:ledger] || 0
      struct[:code] = transfer[:code] || 0
      struct[:flags] = transfer[:flags] || 0
    end

    def copy_account_filter_to_buffer(buffer, filter)
      struct = FFI::AccountFilter.new(buffer)

      write_uint128(struct[:account_id].to_ptr, filter[:account_id] || 0)
      write_uint128(struct[:user_data_128].to_ptr, filter[:user_data_128] || 0)
      struct[:user_data_64] = filter[:user_data_64] || 0
      struct[:user_data_32] = filter[:user_data_32] || 0
      struct[:code] = filter[:code] || 0
      struct[:timestamp_min] = filter[:timestamp_min] || 0
      struct[:timestamp_max] = filter[:timestamp_max] || 0
      struct[:limit] = filter[:limit] || 0
      struct[:flags] = filter[:flags] || 0
    end

    def copy_query_filter_to_buffer(buffer, filter)
      struct = FFI::QueryFilter.new(buffer)

      write_uint128(struct[:user_data_128].to_ptr, filter[:user_data_128] || 0)
      struct[:user_data_64] = filter[:user_data_64] || 0
      struct[:user_data_32] = filter[:user_data_32] || 0
      struct[:ledger] = filter[:ledger] || 0
      struct[:code] = filter[:code] || 0
      struct[:timestamp_min] = filter[:timestamp_min] || 0
      struct[:timestamp_max] = filter[:timestamp_max] || 0
      struct[:limit] = filter[:limit] || 0
      struct[:flags] = filter[:flags] || 0
    end

    def parse_results(data, struct_class)
      return [] if data.nil? || data.empty?

      count = data.bytesize / struct_class.size
      ptr = ::FFI::MemoryPointer.from_string(data)

      count.times.map do |i|
        struct = struct_class.new(ptr + i * struct_class.size)
        struct_to_hash(struct)
      end
    end

    def struct_to_hash(struct)
      result = {}
      struct.members.each do |member|
        value = struct[member]
        result[member] = if value.is_a?(FFI::UINT128)
          (value[:hi] << 64) | value[:lo]
        elsif value.is_a?(Array) && value.all? { |v| v.is_a?(Symbol) }
          # FFI bitmask returns array of symbols - read raw integer from memory
          read_raw_flags(struct, member)
        else
          value
        end
      end
      result
    end

    # Bitmask fields need to be read as raw integers for consistency
    BITMASK_SIZES = {
      FFI::AccountFlags => 2,      # uint16
      FFI::TransferFlags => 2,     # uint16
      FFI::AccountFilterFlags => 4, # uint32
      FFI::QueryFilterFlags => 4    # uint32
    }.freeze

    def read_raw_flags(struct, member)
      offset = struct.class.offset_of(member)
      layout_field = struct.class.layout[member]
      native_type = layout_field.type.native_type

      case native_type.size
      when 2 then struct.to_ptr.get_uint16(offset)
      when 4 then struct.to_ptr.get_uint32(offset)
      else struct.to_ptr.get_uint64(offset)
      end
    end
  end
end
