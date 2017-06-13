require 'store_mixin'
require "log_helper"

class OrderStore # < RedisStore
  include LogHelper
  include Store

  def initialize
    #show_info "OrderStore#initialize"
    super
  end
end

