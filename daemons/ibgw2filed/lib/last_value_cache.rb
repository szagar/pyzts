$: << "#{ENV['ZTS_HOME']}/etc"

require "singleton"

require "store_mixin"
require "log_helper"

class LastValueCache
  include Singleton  
  include LogHelper  
  include Store  

  #attr_reader :redis

  def initialize
    #debug "LastValueCache#initialize"
    #$redis ||= RedisFactory2.new.client
  end

  def mkt_bias
    (redis_md.hget "lvc:mkt", "bias") || "NA"
  rescue
    "NA"
  end

  def mkt_energy
    (redis_md.hget "lvc:mkt", "energy") || "NA"
  rescue
    "NA"
  end

  def new_high(sec_id)
    close > (redis_md.hget "lvc:stock:#{sec_id}", "all_time_high").to_f
  rescue
    false
  end

  def high(sec_id)
    (redis_md.hget "lvc:stock:#{sec_id}", "high").to_f
  end

  def low(sec_id)
    (redis_md.hget "lvc:stock:#{sec_id}", "low").to_f
  end

  def close(sec_id)
    (redis_md.hget "lvc:stock:#{sec_id}", "close").to_f
  end

  def last(sec_id)
    #debug "last(#{sec_id})"
    (redis_md.hget "lvc:stock:#{sec_id}", "close").to_f
  end

  def status(sec_id)
    (redis_md.hget "lvc:stock:#{sec_id}", "status")
  end

  def atr(sec_id)
    (redis_md.hget "lvc:stock:#{sec_id}", "atr14d").to_f
  end

  def ema(sec_id,level,period)
    #show_info "(redis.hget lvc:stock:#{sec_id}, ema#{period}_#{level}).to_f"
    (redis_md.hget "lvc:stock:#{sec_id}", "ema#{period}_#{level}").to_f
  end

  def bar_time(sec_id)
    (redis_md.hget "lvc:stock:#{sec_id}", "time").to_f
  end

  def exists?(field,sec_id)
    valid_price?((redis_md.hget "lvc:stock:#{sec_id}", field).to_f) rescue false
  end

  def update(sec_id, field, value)
    redis_md.hset "lvc:stock:#{sec_id}", field, value
  end

  #######
  private
  #######

  def valid_price?(price)
    (price.is_a?(Numeric) && price > 0.0)
  end

end
