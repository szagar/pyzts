require "singleton"
require "store_mixin"
#require "redis_factory"
require "zts_constants"
require "log_helper"
require "ostruct"

class BrokerOrders
  include Singleton
  include ZtsConstants
  include Store
  include LogHelper

  #attr_accessor :redis

  def initialize
    show_info "BrokerOrders#initialize"
    #redis ||= RedisFactory.instance.client
  end
  
  def all_orders(broker_account)
    broker_accounts = (broker_account == "*" ? (redis.keys "brokerOrderStatus:*").map {|k|
                                                k[/brokerOrderStatus:(\w*)/,1]}
                                             : Array(broker_account))
    broker_accounts.map do |ba|
      (redis.zrange "brokerOrderStatus:#{ba}", 0, 100, :withscores => true).sort.collect do |pos_id, status|
        status_human =  OrderStatusHuman[status.to_i.to_s]
        order = OpenStruct.new(redis.hgetall "brokerOrder:#{pos_id}")
        order.status_human = status_human
        #printf "%11s%5s => %s\n",ba,pos_id,OrderStatusHuman[status.to_i.to_s]
        order
      end
    end.flatten
  end

  ###################
  private
  ###################
end
