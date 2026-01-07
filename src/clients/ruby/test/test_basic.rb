# frozen_string_literal: true

require_relative "test_helper"

class TestBasic < Minitest::Test
  def setup
    @client = TBClient::Client.new
    @callback = proc { |*args| on_completion(*args) }

    cluster_id_ptr = TBClient::UINT128.new
    cluster_id_ptr[:lo] = CLUSTER_ID % (2**64)
    cluster_id_ptr[:hi] = CLUSTER_ID >> 64

    status = TBClient.tb_client_init(@client, cluster_id_ptr, ADDRESS, ADDRESS.length, 1, @callback)
    assert_equal :SUCCESS, status, "Failed to initialize client: #{status}"
  end

  def teardown
    TBClient.tb_client_deinit(@client) if @client
  end

  def on_completion(client_id, packet, timestamp, result_ptr, result_len)
    # TODO: Handle completion callback
  end

  def test_client_initializes
    # If we got here, setup succeeded
    assert @client
  end
end
