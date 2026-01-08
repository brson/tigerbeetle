# frozen_string_literal: true

require_relative "test_helper"
require "tigerbeetle"
require "securerandom"

class TestClient < Minitest::Test
  def setup
    @address = ENV.fetch("TB_ADDRESS", "3001")
    @cluster_id = ENV.fetch("TB_CLUSTER_ID", "0").to_i
    @client = TigerBeetle::Client.new(@cluster_id, @address)
  end

  def teardown
    @client&.close
  end

  def test_client_init_and_close
    assert @client
  end

  def test_create_account
    account_id = random_id

    results = @client.create_accounts([{
      id: account_id,
      ledger: 1,
      code: 1,
      flags: 0
    }])

    # Empty results means success
    assert_equal [], results
  end

  def test_create_account_duplicate
    account_id = random_id

    # First create succeeds
    results = @client.create_accounts([{
      id: account_id,
      ledger: 1,
      code: 1,
      flags: 0
    }])
    assert_equal [], results

    # Second create returns EXISTS
    results = @client.create_accounts([{
      id: account_id,
      ledger: 1,
      code: 1,
      flags: 0
    }])
    assert_equal 1, results.size
    assert_equal 0, results[0][:index]
    assert_equal :EXISTS, results[0][:result]
  end

  def test_lookup_account
    account_id = random_id

    # Create account
    @client.create_accounts([{
      id: account_id,
      ledger: 1,
      code: 718,
      flags: 0,
      user_data_128: 12345,
      user_data_64: 67890,
      user_data_32: 111
    }])

    # Lookup
    accounts = @client.lookup_accounts([account_id])
    assert_equal 1, accounts.size

    account = accounts[0]
    assert_equal account_id, account[:id]
    assert_equal 1, account[:ledger]
    assert_equal 718, account[:code]
    assert_equal 12345, account[:user_data_128]
    assert_equal 67890, account[:user_data_64]
    assert_equal 111, account[:user_data_32]
  end

  def test_lookup_nonexistent_account
    accounts = @client.lookup_accounts([random_id])
    assert_equal [], accounts
  end

  def test_create_transfer
    debit_id = random_id
    credit_id = random_id
    transfer_id = random_id

    # Create accounts first
    @client.create_accounts([
      { id: debit_id, ledger: 1, code: 1, flags: 0 },
      { id: credit_id, ledger: 1, code: 1, flags: 0 }
    ])

    # Create transfer
    results = @client.create_transfers([{
      id: transfer_id,
      debit_account_id: debit_id,
      credit_account_id: credit_id,
      amount: 100,
      ledger: 1,
      code: 1,
      flags: 0
    }])

    assert_equal [], results
  end

  def test_lookup_transfer
    debit_id = random_id
    credit_id = random_id
    transfer_id = random_id

    # Create accounts
    @client.create_accounts([
      { id: debit_id, ledger: 1, code: 1, flags: 0 },
      { id: credit_id, ledger: 1, code: 1, flags: 0 }
    ])

    # Create transfer
    @client.create_transfers([{
      id: transfer_id,
      debit_account_id: debit_id,
      credit_account_id: credit_id,
      amount: 500,
      ledger: 1,
      code: 99,
      flags: 0
    }])

    # Lookup
    transfers = @client.lookup_transfers([transfer_id])
    assert_equal 1, transfers.size

    transfer = transfers[0]
    assert_equal transfer_id, transfer[:id]
    assert_equal debit_id, transfer[:debit_account_id]
    assert_equal credit_id, transfer[:credit_account_id]
    assert_equal 500, transfer[:amount]
    assert_equal 1, transfer[:ledger]
    assert_equal 99, transfer[:code]
  end

  def test_account_balances_after_transfer
    debit_id = random_id
    credit_id = random_id

    # Create accounts
    @client.create_accounts([
      { id: debit_id, ledger: 1, code: 1, flags: 0 },
      { id: credit_id, ledger: 1, code: 1, flags: 0 }
    ])

    # Create transfer
    @client.create_transfers([{
      id: random_id,
      debit_account_id: debit_id,
      credit_account_id: credit_id,
      amount: 100,
      ledger: 1,
      code: 1,
      flags: 0
    }])

    # Check balances
    accounts = @client.lookup_accounts([debit_id, credit_id])
    assert_equal 2, accounts.size

    debit_account = accounts.find { |a| a[:id] == debit_id }
    credit_account = accounts.find { |a| a[:id] == credit_id }

    assert_equal 100, debit_account[:debits_posted]
    assert_equal 0, debit_account[:credits_posted]
    assert_equal 0, credit_account[:debits_posted]
    assert_equal 100, credit_account[:credits_posted]
  end

  def test_get_account_transfers
    # Create account with HISTORY flag to enable balance tracking
    account_id = random_id
    other_id = random_id

    @client.create_accounts([
      { id: account_id, ledger: 1, code: 1, flags: TigerBeetle::FFI::AccountFlags[:HISTORY] },
      { id: other_id, ledger: 1, code: 1, flags: 0 }
    ])

    # Create some transfers
    5.times do |i|
      @client.create_transfers([{
        id: random_id,
        debit_account_id: account_id,
        credit_account_id: other_id,
        amount: 100 + i,
        ledger: 1,
        code: 1,
        flags: 0
      }])
    end

    # Query transfers for the account
    filter = {
      account_id: account_id,
      timestamp_min: 0,
      timestamp_max: 0,
      limit: 10,
      flags: TigerBeetle::FFI::AccountFilterFlags[:DEBITS] | TigerBeetle::FFI::AccountFilterFlags[:CREDITS]
    }
    transfers = @client.get_account_transfers(filter)

    assert_equal 5, transfers.size

    # Verify timestamps are ascending
    prev_ts = 0
    transfers.each do |t|
      assert t[:timestamp] > prev_ts
      prev_ts = t[:timestamp]
    end
  end

  def test_get_account_balances
    # Create account with HISTORY flag
    account_id = random_id
    other_id = random_id

    @client.create_accounts([
      { id: account_id, ledger: 1, code: 1, flags: TigerBeetle::FFI::AccountFlags[:HISTORY] },
      { id: other_id, ledger: 1, code: 1, flags: 0 }
    ])

    # Create transfers
    3.times do
      @client.create_transfers([{
        id: random_id,
        debit_account_id: account_id,
        credit_account_id: other_id,
        amount: 100,
        ledger: 1,
        code: 1,
        flags: 0
      }])
    end

    # Query balance history
    filter = {
      account_id: account_id,
      timestamp_min: 0,
      timestamp_max: 0,
      limit: 10,
      flags: TigerBeetle::FFI::AccountFilterFlags[:DEBITS] | TigerBeetle::FFI::AccountFilterFlags[:CREDITS]
    }
    balances = @client.get_account_balances(filter)

    assert_equal 3, balances.size

    # Verify debits_posted increases
    balances.each_with_index do |b, i|
      assert_equal (i + 1) * 100, b[:debits_posted]
    end
  end

  def test_query_accounts
    # Create accounts with specific user_data for querying
    marker = random_id
    5.times do
      @client.create_accounts([{
        id: random_id,
        ledger: 1,
        code: 999,
        flags: 0,
        user_data_128: marker
      }])
    end

    # Query by user_data_128 and code
    filter = {
      user_data_128: marker,
      user_data_64: 0,
      user_data_32: 0,
      ledger: 1,
      code: 999,
      timestamp_min: 0,
      timestamp_max: 0,
      limit: 10,
      flags: 0
    }
    accounts = @client.query_accounts(filter)

    assert_equal 5, accounts.size
    accounts.each do |a|
      assert_equal marker, a[:user_data_128]
      assert_equal 999, a[:code]
    end
  end

  def test_query_transfers
    # Create accounts
    debit_id = random_id
    credit_id = random_id
    marker = random_id

    @client.create_accounts([
      { id: debit_id, ledger: 1, code: 1, flags: 0 },
      { id: credit_id, ledger: 1, code: 1, flags: 0 }
    ])

    # Create transfers with specific user_data for querying
    5.times do
      @client.create_transfers([{
        id: random_id,
        debit_account_id: debit_id,
        credit_account_id: credit_id,
        amount: 50,
        ledger: 1,
        code: 888,
        flags: 0,
        user_data_128: marker
      }])
    end

    # Query by user_data_128 and code
    filter = {
      user_data_128: marker,
      user_data_64: 0,
      user_data_32: 0,
      ledger: 1,
      code: 888,
      timestamp_min: 0,
      timestamp_max: 0,
      limit: 10,
      flags: 0
    }
    transfers = @client.query_transfers(filter)

    assert_equal 5, transfers.size
    transfers.each do |t|
      assert_equal marker, t[:user_data_128]
      assert_equal 888, t[:code]
      assert_equal 50, t[:amount]
    end
  end

  def test_query_with_pagination
    # Create accounts with marker
    marker = random_id
    10.times do
      @client.create_accounts([{
        id: random_id,
        ledger: 1,
        code: 777,
        flags: 0,
        user_data_128: marker
      }])
    end

    # Query first 5
    filter = {
      user_data_128: marker,
      code: 777,
      ledger: 1,
      timestamp_min: 0,
      timestamp_max: 0,
      limit: 5,
      flags: 0
    }
    first_page = @client.query_accounts(filter)
    assert_equal 5, first_page.size

    # Query next 5 using timestamp_min
    last_ts = first_page.last[:timestamp]
    filter[:timestamp_min] = last_ts + 1
    second_page = @client.query_accounts(filter)
    assert_equal 5, second_page.size

    # Verify no overlap
    first_ids = first_page.map { |a| a[:id] }
    second_ids = second_page.map { |a| a[:id] }
    assert_empty first_ids & second_ids
  end

  def test_query_reversed
    # Create accounts
    marker = random_id
    5.times do
      @client.create_accounts([{
        id: random_id,
        ledger: 1,
        code: 666,
        flags: 0,
        user_data_128: marker
      }])
    end

    # Query ascending (default)
    filter = {
      user_data_128: marker,
      code: 666,
      ledger: 1,
      timestamp_min: 0,
      timestamp_max: 0,
      limit: 10,
      flags: 0
    }
    asc = @client.query_accounts(filter)

    # Query descending
    filter[:flags] = TigerBeetle::FFI::QueryFilterFlags[:REVERSED]
    desc = @client.query_accounts(filter)

    assert_equal 5, asc.size
    assert_equal 5, desc.size

    # Verify order is reversed
    assert_equal asc.map { |a| a[:id] }, desc.map { |a| a[:id] }.reverse
  end

  def test_create_accounts_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.create_accounts([{ id: random_id, ledger: 1, code: 1, flags: 0 }])
    end
  end

  def test_create_transfers_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.create_transfers([{
        id: random_id,
        debit_account_id: random_id,
        credit_account_id: random_id,
        amount: 100,
        ledger: 1,
        code: 1,
        flags: 0
      }])
    end
  end

  def test_lookup_accounts_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.lookup_accounts([random_id])
    end
  end

  def test_lookup_transfers_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.lookup_transfers([random_id])
    end
  end

  def test_get_account_transfers_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.get_account_transfers({
        account_id: random_id,
        timestamp_min: 0,
        timestamp_max: 0,
        limit: 10,
        flags: TigerBeetle::FFI::AccountFilterFlags[:DEBITS] | TigerBeetle::FFI::AccountFilterFlags[:CREDITS]
      })
    end
  end

  def test_get_account_balances_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.get_account_balances({
        account_id: random_id,
        timestamp_min: 0,
        timestamp_max: 0,
        limit: 10,
        flags: TigerBeetle::FFI::AccountFilterFlags[:DEBITS] | TigerBeetle::FFI::AccountFilterFlags[:CREDITS]
      })
    end
  end

  def test_query_accounts_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.query_accounts({
        user_data_128: 0,
        ledger: 1,
        code: 1,
        timestamp_min: 0,
        timestamp_max: 0,
        limit: 10,
        flags: 0
      })
    end
  end

  def test_query_transfers_after_close
    client = TigerBeetle::Client.new(@cluster_id, @address)
    client.close

    assert_raises(TigerBeetle::Client::SubmitError) do
      client.query_transfers({
        user_data_128: 0,
        ledger: 1,
        code: 1,
        timestamp_min: 0,
        timestamp_max: 0,
        limit: 10,
        flags: 0
      })
    end
  end

  private

  def random_id
    # Generate random 128-bit ID
    SecureRandom.random_number(2**128)
  end
end
