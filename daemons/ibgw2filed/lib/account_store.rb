#$: << "#{ENV['ZTS_HOME']}/etc"
require "zts_constants"
require "store_mixin"
require "log_helper"
#require "redis_store"
require "s_n"

class AccountStore # < RedisStore
  include Store
  include LogHelper
  include ZtsConstants

  attr_reader :sequencer

  def initialize
    @sequencer = SN.instance
    super
  end

  def create(params)
    show_action "AccountStore#create: account_name: #{params[:account_name]}"
    params['account_id'] = next_id
    account_name = params[:account_name]
    params.each do |k,v|
      redis.hset pk(account_name), k ,v
    end
    account_name
  end

  def members(name)
    redis.hkeys pk(name)
  end

  def add_setup(account, setup)
    redis.sadd setup_key(account), setup
  end

  def rm_setup(account, setup)
    redis.srem setup_key(account), setup
  end

  def setups(account)
    redis.smembers setup_key(account)
  end

  def deposit(account, amount)
    redis.hset pk(account), "net_deposits", net_deposits(account) + amount
    balance(account)
  end

  def withdraw(account, amount)
    redis.hset pk(account), "net_withdraws", net_withdraws(account) - amount
    balance(account)
  end

  #def add_commissions(account, amount)
  #  redis.hset pk(account), "total_commissions", total_commissions(account) + amount
  #end

  def balance(account)
    net_deposits(account) - net_withdraws(account)
  end

  def net_deposits(account)
    (redis.hget pk(account), "net_deposits" || 0.0).to_f
  end

  def net_withdraws(account)
    (redis.hget pk(account), "net_withdraws" || 0.0).to_f
  end

  def total_commissions(account)
    (redis.hget pk(account), "total_commissions").to_f
  end

  # refactore to PositionStore
  def open_positions_by_account(name)
    open_positions(name)
  end

  # refactore to PositionStore
  def open_position_ids(name)
    redis.zrangebyscore "portf:#{name}", PosStatus[:open], PosStatus[:open]
  end

  # refactor to PositionStore
  def calc_locked_amount(account)
    open_positions(account).inject(0) do |amt,pos|
      pos['current_stop'].to_f * pos['quantity'].to_f
    end
  end

  def core_equity
    (redis.hget pk(account), "core_equity" || 0.0).to_f
  end

  #######
  private
  #######

  def id_str
    "account_name"
  end

  def next_id
    sequencer.next_account_id
  end

  def setup_key(account)
    "#{pk(account)}:setups"
  end
 
  # refactore to PositionStore
  def open_positions(name)
    ops = []
    (redis.zrangebyscore "portf:#{name}", PosStatus[:open],
                                        PosStatus[:open]).each do |pos_id|
      ops << redis.hgetall("pos:#{pos_id}")
    end
    ops
  end
end
