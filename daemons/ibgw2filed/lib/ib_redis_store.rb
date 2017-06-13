require 'json'
require 's_m'
require 's_n'
require 'store_mixin'
#require 'redis_factory'
require 'zts_constants'
require 'log_helper'

class InvalidExecId < StandardError; end
class CannotAllocate < StandardError; end

class IbRedisStore
  include ZtsConstants
  include LogHelper
  include Store
  
  #attr_reader :redis
  attr_reader :sequencer, :sec_master

  def initialize
    show_info "IbRedisStore#initialize"
    #redis      ||= RedisFactory2.new.client
    @sequencer  = SN.instance
    @sec_master = SM.instance
  end

  def account_persister(json_data)
    fields = %w(AccountCode AccountReady AccountType AccruedCash_S AccruedDividend_S
                AvailableFunds_S BuyingPower CashBalance Cushion EquityWithLoanValue_S
                ExcessLiquidity_S FullAvailableFunds_S FullExcessLiquidity_S
                FullInitMarginReq_S FullMaintMarginReq_S GrossPositionValue_S
                InitMarginReq_S Leverage_S LookAheadAvailableFunds_S LookAheadExcessLiquidity_S
                LookAheadInitMarginReq_S LookAheadMaintMarginReq_S MaintMarginReq_S
                MoneyMarketFundValue MutualFundValue NetDividend NetLiquidation_S
                OptionMarketValue PreviousDayEquityWithLoanValue_S RealizedPnL RegTEquity_S
                RegTMargin_S SMA_S StockMarketValue TotalCashBalance TotalCashValue_S
                TradingType_S UnrealizedPnL WhatIfPMEnabled)
    data = JSON.parse(json_data)
    if fields.include?(data['key']) then
      #puts "redis.hset brokerAccount:#{data['account']}, #{data['key']}, #{data['value']}"
      redis.hset "brokerAccount:#{data['account']}", data['key'], data['value']
    end
  end
  
  def position_persister(json_data)
    data = JSON.parse(json_data)

    fields = %w(ticker position market_price market_value average_cost unrealized_pnl realized_pnl)
    sec_id = sec_master.sec_lookup(data['ticker'])
      
    fields.each do |k|
      redis.hset "brokerPortf:#{data['broker_account']}:#{sec_id}", k, data[k]
    end
  end
  
  def commission_persister(json_data)
    data = JSON.parse(json_data)
    show_info "commission_persister: data = #{data}"
    fields = data.keys.select {|k| data[k]}
    exec_id     = data.fetch('exec_id') {warn "should not be here"}
    persist_rec("commission:#{exec_id}",data)
    pos_id      = pos_id_lookup(exec_id: exec_id)
    comm        = data.fetch("commission") { 0.0 }
    pos_comm    = (redis.hget "pos:#{pos_id}", "commission").to_f || 0.0
    redis.hset "pos:#{pos_id}", "commission", comm + pos_comm
  end
 
  def assign_alloc_commission(exec_id, amount)
    show_info "IbRedisStore#assign_alloc_commission(#{exec_id}, #{amount})"
    search_str =  "alloc:*:#{exec_id}"
    unless (redis.keys search_str).size > 0
      warn "Allocation key(#{search_str}) for commision NOT found!"
      return
    end
    alloc_fill_key = (redis.keys search_str)[0]
    alloc_id       = alloc_fill_key[/alloc:(\d+):.*/,1]
    unless alloc_id.to_i > 0
      raise InvalidExecId, "Could NOT map exec_id(#{exec_id}) to alloc_id" 
    end
    redis.hset alloc_fill_key, "commissions", amount
    alloc_key          = (redis.keys "alloc:*:*:#{alloc_id}")[0]
    current_alloc_comm = redis.hget alloc_key, "commissions"
    redis.hset alloc_key, "commissions", current_alloc_comm.to_f + amount
  rescue => e
    warn e.message
  end

  def execution_persister(fill)
    show_info "execution_persister: fill = #{fill.inspect}"
    exec_id = fill["exec_id"]  #data.fetch('exec_id') {warn "should not be here"}
    persist_rec("execution:#{exec_id}",fill)
  end

  def alloc_fill_persister(alloc_id,fill)
    show_info "alloc_fill_persister: alloc_id=#{alloc_id}, fill = #{fill.inspect}"
    exec_id = fill.exec_id
    alloc_exec_key = "alloc:#{alloc_id}:#{exec_id}"
    persist_rec(alloc_exec_key,fill.attributes)
    queue_alloc_execution(alloc_exec_key)
  end

  def create_update_allocation(account_name, sec_id, quantity, price)
    prefix     = "alloc:#{account_name}:#{sec_id}"
    search_str = "#{prefix}:*"
    results = redis.keys search_str
    alloc_id = (results.size == 0) ? create_new_allocation(prefix)
                                   : String(results)[/alloc:.*\d+:(\d+)/,1]
    update_allocation(alloc_id, quantity, price)
    alloc_id
  rescue => e
    warn e.message
    raise CannotAllocate.new, "from IbRedisStore#create_update_allocation"
  end 

  def order_persister(data)
    show_info "IbRedisStore#order_persister: data = #{data}"
    fields = data.keys.select {|k| data[k]}

    broker_ref     = (data.fetch('broker_ref') {warn "should not be here"}).to_s
    pos_id         = data.fetch('pos_id') {order_lookup(broker_ref)['pos_id']}
    broker_account = data.fetch('broker_account') {
                       order_lookup(broker_ref)['broker_account']}
    fields.each do |k|
      #puts "redis.hset brokerOrder:#{pos_id}, #{k}, #{data[k]}"
      redis.hset "brokerOrder:#{pos_id}", k, data[k]
      redis.hset "brokerOrderMap:#{broker_ref}", "pos_id", pos_id
      redis.hset "brokerOrderMap:#{broker_ref}", "broker_account", broker_account
      redis.zadd("brokerOrderStatus:#{broker_account}",
                 OrderStatus[data[k].to_sym], pos_id) if(k == "status")
    end
    pos_id
  end

  def broker_open_orders(broker_account)
    account = (broker_account == "all") ? "*" : broker_account
    redis.zrangebyscore "brokerOrderStatus:#{account}", OrderStatus[:Submitted], OrderStatus[:Submitted]
  end
 
  def execution_to_book
    k = redis.hgetall pop_alloc_execution
    k.size > 0 ? k : false
  end

  #######
  private
  #######

  def create_new_allocation(prefix)
    show_info "IbRedisStore#create_new_allocation(#{prefix})"
    alloc_id = sequencer.next_alloc_id
    show_info "redis.hmset #{prefix}:#{alloc_id}, quantity, 0.0, price, 0.0, alloc_id, alloc_id"
    redis.hmset "#{prefix}:#{alloc_id}", "quantity", 0.0, "price", 0.0, "alloc_id", alloc_id
    alloc_id
  end

  def update_allocation(alloc_id, quantity, price)
    alloc_key = (redis.keys "alloc:*:*:#{alloc_id}")[0]
    current = redis.hgetall alloc_key
    avg_price = (quantity*price +
                 current["quantity"].to_f*current["price"].to_f) /
                (quantity+current["quantity"].to_f)
    redis.hset alloc_key, "quantity", quantity + current["quantity"].to_i
    show_info "redis.hset #{alloc_key}, price, #{avg_price}"
    redis.hset alloc_key, "price", avg_price
  end

  def queue_alloc_execution(alloc_exec_key)
    redis.rpush "allocs_not_booked", alloc_exec_key
  end

  def pop_alloc_execution
    redis.lpop "allocs_not_booked"
  end

  def order_lookup(broker_ref)
    debug "IbRedisStore#order_lookup(#{broker_ref}): redis.hgetall brokerOrderMap:#{broker_ref}"
    redis.hgetall "brokerOrderMap:#{broker_ref}"
  end

  def pos_id_lookup(params)
    pos_id = false
    if (exec_id = params.fetch(:exec_id))
      pos_id = redis.hget "execution:#{exec_id}", "pos_id"
    end
    pos_id
  end

  def persist_rec(db_key,data)
    fields  = data.keys.select {|k| data[k]}
    fields.each do |k|
      show_info "IbRedisStore#redis.hset #{db_key}, #{k}, #{data[k]}"
      redis.hset db_key, k, data[k]
    end
  end
end
