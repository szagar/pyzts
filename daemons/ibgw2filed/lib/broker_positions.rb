require "singleton"
#require "redis_factory"
require "store_mixin"

class BrokerPositions
  include Singleton
  include Store

  def initialize
    #$redis ||= RedisFactory.instance.client
  end
  
  def hash_list(account_code)
    (redis.keys "brokerPortf:#{account_code}:*").sort.map do |p_key|
      acct = p_key[/.*:(.*):.*/,1]
      h = (redis.hgetall p_key).merge!("account_code" => acct)
    end
  end

  ###################
  private
  ###################
end
