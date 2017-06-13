require 'zts_constants'
#require "redis_store"
require 'store_mixin'
require 'log_helper'

class PortfolioStore # < RedisStore
  include Singleton
  include ZtsConstants
  include LogHelper
  include Store

  def initialize
    #show_info "PortfolioStore#initialize"
    super
  end
  
  def new_position(account_name, pos_id)
    action "PortfolioStore#set position(#{pos_id}) status to :init"
    redis.zadd portf_pk(account_name), PosStatus[:init], pos_id
  end

  def close_position(account_name, pos_id)
    action "PortfolioStore#set position(#{pos_id}) status to :closed"
    redis.zadd portf_pk(account_name), PosStatus[:closed], pos_id
  end

  def cancel_position(account_name, pos_id)
    action "PortfolioStore#set position(#{pos_id}) status to :cancel"
    redis.zadd portf_pk(account_name), PosStatus[:cancel], pos_id
  end

  def open_position(account_name, pos_id)
    action "PortfolioStore#set position(#{pos_id}) status to :open"
    redis.zadd portf_pk(account_name), PosStatus[:open], pos_id
  end

  #def create_timed_exit(pos_id, exit_day)
  #  redis.zadd "exits:timed", exit_day, pos_id
  #end

  def update_position(account_name, pos_id, order_qty, escrow)
    action "set escrow for position(#{pos_id}) to #{escrow}"
    p = get(pos_id)
    p.escrow += escrow
    p.order_qty += order_qty
  end

  def initialize_position(account_name, pos_id)
    action "set position(#{pos_id}) status to :init"
    redis.zadd portf_pk(account_name), PosStatus[:init], pos_id
  end

  def calc_number_of_positions(account_name)
    open_positions(account_name).size
  end

  def calc_number_of_shares(account_name)
    sum = 0
    open_positions(account_name).each do |pos_id|
      pos = (redis.hgetall pos_pk(pos_id))
      sum += pos['quantity']
    end
    sum
  end

  def calc_locked_in_longs(account_name)
    sum = 0.0
    open_positions(account_name).each do |pos_id|
      pos = (redis.hgetall pos_pk(pos_id))
      sum += (pos['current_stop'].to_f * pos['quantity'].to_f).round(2)
    end
    sum
  end

  def calc_long_market_value(account_name)
    sum = 0.0
    open_positions(account_name).each do |pos_id|
      pos = (redis.hgetall pos_pk(pos_id))
      next unless pos['side'] == "long"
      sum += (pos['quantity'].to_f * pos['mark_px'].to_f).round(2)
    end
    sum
  end

  def calc_cost_long_positions(account_name)
    cost = 0.0
    open_positions(account_name).each do |pos_id|
      pos = (redis.hgetall pos_pk(pos_id))
      next unless pos['side'] == "long"
      cost += (pos['quantity'].to_f * pos['avg_entry_px'].to_f).round(3)
    end
    cost
  end

  def init_positions(account_name)
    redis.zrangebyscore portf_pk(account_name), PosStatus[:init], PosStatus[:init]
  end

  def open_positions(account_name)
    #debug "PortfolioStore#open_positions(#{account_name})"
    #debug "results = redis.zrangebyscore #{portf_pk(account_name)}, #{PosStatus[:open]}, #{PosStatus[:open]}"
    results = redis.zrangebyscore portf_pk(account_name), PosStatus[:open], PosStatus[:open]
  end

  def closed_positions(account_name)
    redis.zrangebyscore portf_pk(account_name), PosStatus[:closed], PosStatus[:closed]
  end

  def sids_of_open_positions
    sids = Array.new
    active_account_names.each do |account_name|
      sids << open_positions(account_name).map do |pos_id|
        (redis.hget pos_pk(pos_id), "sec_id")
      end
    end
    sids.flatten.uniq
  end

  def active_account_names
    ((redis.keys 'account*').reject {|e| e =~ /:setups/}).map {|a| a[/account:(.*)/,1]}
  end

  def get(pos_id)
    #debug "PortfolioStore#get(#{pos_id})"
    PositionProxy.new(pos_id: pos_id)
  end

  #######
  private
  #######

  def pos_pk(id)
    "pos:#{id}"
  end

  def acct_pk(name)
    "account:#{name}"
  end

  def portf_pk(name)
    "portf:#{name}"
  end

end
