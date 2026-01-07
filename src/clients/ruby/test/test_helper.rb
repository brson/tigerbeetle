# frozen_string_literal: true

require "minitest/autorun"
require "tb_client"

ADDRESS = ENV.fetch("TB_ADDRESS", "3000")
CLUSTER_ID = ENV.fetch("TB_CLUSTER_ID", "0").to_i
