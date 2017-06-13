$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
require "zts_config"
require "redis"
require "log_helper"

module AccountManagerPersister
  include LogHelper

  extend self

  def whoami
    "AccountManagerPersister"
  end

  def accounts
    (redis.keys pk('*')).reject {|e| e =~ /:setups/}.collect { |name|
      account_detail(name) }
  end

  def account_detail(account)
    result = redis.hgetall account
    result
  end

  def exists?(account)
    redis.keys pk(account)
  end

  def getter(account, field)
    redis.hget pk(account), field
  end

  def add_setup(account, setup)
    redis.sadd setup_key(account), setup
  end

  def set_redis(redis)
    @redis = redis
    SN.set_redis(redis)
  end

  #######
  private
  #######

  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
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
