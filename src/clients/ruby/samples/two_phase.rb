#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "tigerbeetle"
require "securerandom"

def random_id
  SecureRandom.random_number(2**128)
end

address = ENV.fetch("TB_ADDRESS", "3000")
cluster_id = ENV.fetch("TB_CLUSTER_ID", "0").to_i

client = TigerBeetle::Client.new(cluster_id, address)

account1_id = random_id
account2_id = random_id
pending_transfer_id = random_id
post_transfer_id = random_id

begin
  # Create two accounts.
  account_errors = client.create_accounts([
    { id: account1_id, ledger: 1, code: 1, flags: 0 },
    { id: account2_id, ledger: 1, code: 1, flags: 0 }
  ])

  puts "Account errors: #{account_errors.inspect}"
  raise "Expected no account errors" unless account_errors.empty?

  # Start a pending transfer.
  transfer_errors = client.create_transfers([
    {
      id: pending_transfer_id,
      debit_account_id: account1_id,
      credit_account_id: account2_id,
      amount: 500,
      ledger: 1,
      code: 1,
      flags: TigerBeetle::FFI::TransferFlags[:PENDING]
    }
  ])

  puts "Transfer errors: #{transfer_errors.inspect}"
  raise "Expected no transfer errors" unless transfer_errors.empty?

  # Validate accounts pending and posted debits/credits before finishing the two-phase transfer.
  accounts = client.lookup_accounts([account1_id, account2_id])
  raise "Expected 2 accounts" unless accounts.size == 2

  accounts.each do |account|
    case account[:id]
    when account1_id
      raise "Expected debits_posted=0" unless account[:debits_posted] == 0
      raise "Expected credits_posted=0" unless account[:credits_posted] == 0
      raise "Expected debits_pending=500" unless account[:debits_pending] == 500
      raise "Expected credits_pending=0" unless account[:credits_pending] == 0
    when account2_id
      raise "Expected debits_posted=0" unless account[:debits_posted] == 0
      raise "Expected credits_posted=0" unless account[:credits_posted] == 0
      raise "Expected debits_pending=0" unless account[:debits_pending] == 0
      raise "Expected credits_pending=500" unless account[:credits_pending] == 500
    else
      raise "Unexpected account: #{account[:id]}"
    end
  end

  # Create a second transfer posting the first transfer.
  transfer_errors = client.create_transfers([
    {
      id: post_transfer_id,
      debit_account_id: account1_id,
      credit_account_id: account2_id,
      amount: 500,
      pending_id: pending_transfer_id,
      ledger: 1,
      code: 1,
      flags: TigerBeetle::FFI::TransferFlags[:POST_PENDING_TRANSFER]
    }
  ])

  puts "Post transfer errors: #{transfer_errors.inspect}"
  raise "Expected no transfer errors" unless transfer_errors.empty?

  # Validate the contents of all transfers.
  transfers = client.lookup_transfers([pending_transfer_id, post_transfer_id])
  raise "Expected 2 transfers" unless transfers.size == 2

  transfers.each do |transfer|
    case transfer[:id]
    when pending_transfer_id
      pending_flag = TigerBeetle::FFI::TransferFlags[:PENDING]
      raise "Expected PENDING flag on pending transfer" unless (transfer[:flags] & pending_flag) == pending_flag
    when post_transfer_id
      post_flag = TigerBeetle::FFI::TransferFlags[:POST_PENDING_TRANSFER]
      raise "Expected POST_PENDING_TRANSFER flag on post transfer" unless (transfer[:flags] & post_flag) == post_flag
    else
      raise "Unexpected transfer: #{transfer[:id]}"
    end
  end

  # Validate accounts after finishing the two-phase transfer.
  accounts = client.lookup_accounts([account1_id, account2_id])
  raise "Expected 2 accounts" unless accounts.size == 2

  accounts.each do |account|
    case account[:id]
    when account1_id
      raise "Expected debits_posted=500" unless account[:debits_posted] == 500
      raise "Expected credits_posted=0" unless account[:credits_posted] == 0
      raise "Expected debits_pending=0" unless account[:debits_pending] == 0
      raise "Expected credits_pending=0" unless account[:credits_pending] == 0
    when account2_id
      raise "Expected debits_posted=0" unless account[:debits_posted] == 0
      raise "Expected credits_posted=500" unless account[:credits_posted] == 500
      raise "Expected debits_pending=0" unless account[:debits_pending] == 0
      raise "Expected credits_pending=0" unless account[:credits_pending] == 0
    else
      raise "Unexpected account: #{account[:id]}"
    end
  end

  puts "ok"
ensure
  client.close
end
