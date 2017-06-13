$: << "#{ENV['ZTS_HOME']}/etc"
require "store_mixin"
require "account_proxy"

class AccountMgrStore # < RedisStore
  include Store

  def initialize
    super
  end

  def accounts(*args)
    args = Array('*') unless args.size > 0
    results = []
    args.each do |name|
      results << (redis.keys pk(name)).reject {|e| e =~ /:setups/}.collect { |account_key|
                  AccountProxy.new(account_name: account_key[/account:(.*)/,1]) }
    end
    results.flatten
  end

  def account(name)
    debug "AccountMgrStore#account(#{name})"
    AccountProxy.new(account_name: name)
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
    "account:#{name}"
  end

  def setup_key(account)
    "#{pk(account)}:setups"
  end
 
  # refactore to PositionStore
  def open_positions(name)
    ops = []
    (redis.zrangebyscore "portf:#{name}", PosStatus[:open],
                                        PosStatus[:open]).each do |pos_id|
      track "AccountMgrStore#open_positions: pos_id=#{pos_id}"
      ops << redis.hgetall("pos:#{pos_id}")
    end
    ops
  end
end
