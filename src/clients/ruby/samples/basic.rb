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
transfer_id = random_id

begin
  # Create two accounts.
  account_errors = client.create_accounts([
    { id: account1_id, ledger: 1, code: 1, flags: 0 },
    { id: account2_id, ledger: 1, code: 1, flags: 0 }
  ])

  puts "Account errors: #{account_errors.inspect}"
  raise "Expected no account errors" unless account_errors.empty?

  # Create a transfer between the accounts.
  transfer_errors = client.create_transfers([
    {
      id: transfer_id,
      debit_account_id: account1_id,
      credit_account_id: account2_id,
      amount: 10,
      ledger: 1,
      code: 1,
      flags: 0
    }
  ])

  puts "Transfer errors: #{transfer_errors.inspect}"
  raise "Expected no transfer errors" unless transfer_errors.empty?

  # Lookup accounts and verify balances.
  accounts = client.lookup_accounts([account1_id, account2_id])
  raise "Expected 2 accounts" unless accounts.size == 2

  accounts.each do |account|
    case account[:id]
    when account1_id
      raise "Unexpected debits_posted for account 1" unless account[:debits_posted] == 10
      raise "Unexpected credits_posted for account 1" unless account[:credits_posted] == 0
    when account2_id
      raise "Unexpected debits_posted for account 2" unless account[:debits_posted] == 0
      raise "Unexpected credits_posted for account 2" unless account[:credits_posted] == 10
    else
      raise "Unexpected account: #{account[:id]}"
    end
  end

  puts "ok"
ensure
  client.close
end
