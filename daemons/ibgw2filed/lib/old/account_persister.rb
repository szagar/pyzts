$: << "#{ENV['ZTS_HOME']}/lib"
require "zts_constants"
require "redis"
require "s_n"
require "log_helper"

module AccountPersister
  include ZtsConstants
  include LogHelper

  extend self

  def whoami
    "AccountPersister"
  end

  def exists?(account)
    redis.keys pk(account)
  end

  def create(account, params)
    params[:account_id] = next_id
    params.each do |k,v|
      redis.hset pk(account), k, v
    end
  end

  def getter(account, field)
    redis.hget pk(account), field
  end

  def add_setup(account, setup)
    redis.sadd setup_key(account), setup
  end

  #def rm_setup(account, setup)
  #  redis.sadd setup_key(account), setup
  #end

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

  def add_commissions(account, amount)
    redis.hset pk(account), "total_commissions", total_commissions(account) + amount
  end

  def balance(account)
    net_deposits(account) - net_withdraws(account)
  end

  def set_redis(redis)
    @redis = redis
    SN.set_redis(redis)
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
    redis.zrangebyscore "poz:#{name}", PosStatus[:open], PosStatus[:open]
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

  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end

  def next_id
    SN.next_account_id
  end

  def pk(name)
    "account:#{name}"
  end

  def setup_key(account)
    "#{pk(account)}:setups"
  end
 
  # refactore to PositionStore
  def open_positions(name)
    ops = []
    (redis.zrangebyscore "poz:#{name}", PosStatus[:open],
                                        PosStatus[:open]).each do |pos_id|
      track "AccountPersister#open_positions: pos_id=#{pos_id}"
      ops << redis.hgetall("pos:#{pos_id}")
    end
    ops
  end
end
