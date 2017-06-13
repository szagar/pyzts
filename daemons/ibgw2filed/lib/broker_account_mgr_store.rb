$: << "#{ENV['ZTS_HOME']}/etc"
require "store_mixin"
require 'ostruct'

class BrokerAccountMgrStore # < RedisStore
  include Store

  def initialize
    show_info "BrokerAccountMgrStore#initialize"
    super
  end
 
  def accounts
    (redis.keys pk('*')).collect { |account_key|
        OpenStruct.new(account_details(account_key))
    }
  end

  def account_detail(account)
    result = redis.hgetall account
    result
  end

  def exists?(name)
    redis.keys pk(name)
  end

  def add_setup(account, setup)
    redis.sadd setup_key(account), setup
  end

  #######
  private
  #######

  def pk(name)
    "brokerAccount:#{name}"
  end

  def account_details(account_key)
    redis.hgetall account_key
  end
end
