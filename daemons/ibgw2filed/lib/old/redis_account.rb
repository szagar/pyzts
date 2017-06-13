$: << "#{ENV['ZTS_HOME']}/etc"
require "zts_config"
require 'zts_constants'
require 's_n'
require 'launchd_helper'

module RedisAccount
  include ZtsConstants
  include LaunchdHelper
  require "redis"
  
  extend self
  
  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    
  end
  
  def next_id
    SN.next_account_id
  end
    
  def pk(name)
    "account:#{name}"
  end
  
  def setup_key(name)
    "#{pk(name)}:setups"
  end
  
  
  def create(args)
    #puts "Account#create"
    name = args[:name]
    #puts "Account#create:  @id = #{id}"
    
    redis.hset pk(name), "account_id",        args[:account_id]
    
    redis.hset pk(name), "name", name
    
    redis.hset pk(name), "money_mgr", args[:money_mgr]
    redis.hset pk(name), "position_percent", args[:position_percent] || 0.0
    redis.hset pk(name), "cash", args[:cash]
    redis.hset pk(name), "net_deposits", args[:net_deposits]
    redis.hset pk(name), "core_equity", args[:cash]
    redis.hset pk(name), "equity_value", "0"
    redis.hset pk(name), "locked_amount", "0"
    redis.hset pk(name), "atr_factor", args[:atr_factor] || "0"
    redis.hset pk(name), "min_shares", args[:min_shares] || "0"
    redis.hset pk(name), "lot_size", args[:lot_size] || "1"
    redis.hset pk(name), "equity_model", args[:equity_model] || "RTEM"
    
    redis.hset pk(name), "broker", args[:broker]
    redis.hset pk(name), "broker_AccountCode", args[:broker_AccountCode]

    redis.hset pk(name), "number_positions", "0"
    redis.hset pk(name), "risk_dollars", args[:risk_dollars] || "0"
    redis.hset pk(name), "reliability", "0"
    redis.hset pk(name), "expectancy", "0"
    redis.hset pk(name), "sharpe_ratio", "0"
    redis.hset pk(name), "vantharp_ratio", "0"
  
    redis.hset pk(name), "realized", "0"
    redis.hset pk(name), "unrealized", "0"
    
    redis.hset pk(name), "maxRp", "-999"
    redis.hset pk(name), "maxRm", "999"
    
    redis.hset pk(name), "date_first_trade", ""
    redis.hset pk(name), "date_last_trade", ""

    redis.hset pk(name), "status", "active"
  end
  

  
  def set(name, args)
    args.each do |k,v|
      redis.hset pk(name), k, v
    end
    #redis.publish "position:update", args.merge(pos_id: id)
  end
  
  def get(name)
    Hash[(redis.hgetall pk(name)).map{|(k,v)| [k.to_sym,v]}]
  end
  
  def setter(name, field, value)
    redis.hset pk(name), field, value
  end
  
  def getter(name, field)
    redis.hget pk(name), field
  end
  
  def open_position_ids(name)
    redis.zrangebyscore "poz:#{name}", PosStatus[:open], PosStatus[:open]
  end

  def open_positions(name)
    ops = []
    lstdout "redis.zrangebyscore poz:#{name}, #{PosStatus[:open]}, #{PosStatus[:open]}"
    (redis.zrangebyscore "poz:#{name}", PosStatus[:open], PosStatus[:open]).each do |pos_id|
      lstdout "pos_id=#{pos_id}"
      ops << redis.hgetall("pos:#{pos_id}")
    end
    lstdout "#open_postions:#{ops}"
    ops
  end

  def calc_locked_amount(name)
    positions = redis.zrangebyscore "poz:#{name}", PosStatus[:open], PosStatus[:open]
    locked = 0
    positions.each do |pos_id|
      pos = RedisPosition.get(pos_id)
      locked += (pos[:current_stop] || 0).to_i * (pos[:quantity] || 0).to_i
    end
    redis.hset pk(name), "locked_amount", locked
  end
  
  def deposit(name,amount)
    net_deposits = redis.hget pk(name), "net_deposits"
    redis.hset pk(name), "net_deposits", net_deposits + amount
  end
  
  def withdraw(name,amount)
    net_deposits = redis.hget pk(name), "net_deposits"
    redis.hset pk(name), "net_deposits", net_deposits - amount
  end
  
  def add_setup(name, setup)
    redis.sadd setup_key(name), setup
  end
  
  def setups(name)
    redis.smembers setup_key(name)
  end
end
