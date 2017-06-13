require "singleton"
require "store_mixin"
require "last_value_cache"
require "log_helper"

SubsKey   = "md:subs"

#MaxRetries = 30
class BarDataError  < StandardError; end

class MktSubscriptions
  include Singleton
  include LogHelper
  include Store

  #attr_reader :mkt_redis

  def initialize
    show_info "MktSubscriptions#initialize"
    #@mkt_redis ||= redis_md
    @lvc       ||= LastValueCache.instance
  end
  
  def add_sid(sid)
    puts "redis_md.sadd #{SubsKey}, #{sid}"
    redis_md.sadd SubsKey, sid   # returns false if sid already member
  end
 
  def rm_sid(sid)
    debug "MktSubscriptions#rm_sid(#{sid})"
    debug "MktSubscriptions#rm_sid caller: #{caller_locations(1,1)[0].label}"
    redis_md.srem SubsKey, sid
    #redis_md.del "#{SubsKey}:#{sid}"
  end

  def sids(tkr_plant=false)
    #debug "sids: redis_md.smembers #{SubsKey}"
    results = redis_md.smembers SubsKey
    tkr_plant ? results.map { |sid| (redis_md.hget "#{SubsKey}:#{sid}", "ticker_plant") == tkr_plant } : results
  end

  def sids_with_data
    (redis_md.keys "md:subs:*").map { |k| k[/md:subs:(\d+)/,1] }
  end


  def exists?(sid)
    (redis_md.sismember SubsKey, sid) == true
  end

  def data_exists?(sid)
    redis_md.exists "#{SubsKey}:#{sid}"
  end

  def ticker_plant(sid)
    redis_md.hget "#{SubsKey}:#{sid}", "ticker_plant"
  end

  #def set_ttl(sid)
  #  redis_md.expire "#{SubsKey}:#{sid}", 10
  #end

  def refresh(sid)
    redis_md.hset "#{SubsKey}:#{sid}", "time", Time.now.to_i
  end

  def subscribe(sid)
    add_sid(sid)
  end

  def unsubscribe(sid,type=false)
    debug "MktSubscriptions#unsubscribe: redis_md.del #{SubsKey}:#{sid}"
    reset_retry(sid)
    rm_sid(sid)
  end

  def size
    redis_md.scard SubsKey
  end

  def clear
    sids.each do |sid|
      rm_sid sid
    end
  end

  def stale?(sid)
    is_redis_time_stale?(sid)
  end

  def active_list
    sids.reject {|sid| stale?(sid)}
  end

  def stale_list
    #debug "stale_list"
    sids.select {|sid| puts "sid ...... #{sid}";stale?(sid)}
  end

  def retry_sid(sid)
    increment_retry(sid)
  end

  def bar_time(sid)
    (redis_md.hget pk(sid), "time").to_i
  rescue
    raise BarDataError, "error retrieving bar time #{pk(sid)}"
  end

  def bar_time_str(sid)
    Time.at(bar_time(sid)).strftime("%T")
  rescue
    raise BarDataError, "error retrieving bar time string #{pk(sid)}"
  end

  def is_active?(sid)
    status = (redis_md.hget pk(sid), "status") 
    (status == "active" || "" || (! status))
  end

  def bar5s_active?(sid)
    is_active?(sid) && bar5s?(sid)
  end

  def is_suspended?(sid)
    (redis_md.hget pk(sid), "status") == "suspended"
  end

  def activate(sid,ticker_plant)
    debug "redis_md.hset #{pk(sid)}, ticker_plant, #{ticker_plant}"
    redis_md.hset pk(sid), "ticker_plant", ticker_plant
    debug "redis_md.hset #{pk(sid)}, status, active"
    redis_md.hset pk(sid), "status", "active"
    debug "redis_md.hset #{pk(sid)}, bar5s,  on"
    redis_md.hset pk(sid), "bar5s",  "on"
  end

  def suspend(sid)
    debug "suspend: (redis_md.hset #{pk(sid)}, status, suspended) if #{is_active?(sid)}"
    (redis_md.hset pk(sid), "status", "suspended") if is_active?(sid)
  end

  def unsuspend(sid)
    debug "suspend: (redis_md.hset #{pk(sid)}, status, active) if #{is_suspended?(sid)}"
    (redis_md.hset pk(sid), "status", "active") if is_suspended?(sid)
    reset_retry(sid)
  end

  ###################
  private
  ###################

  def threshold_time(secs)
    Time.now.to_i - secs
  end

  def is_redis_time_stale?(sid,threshold=20)
    #debug "sid:#{sid} => ((#{Time.now.to_i} - #{bar_time(sid)}) > #{threshold}) && #{is_active?(sid)}"
    ((Time.now.to_i - bar_time(sid)) > threshold) && is_active?(sid)
  rescue BarDataError => e
    warn "#{e}"
    true
  end    

  def increment_retry(sid)
    attempts = (redis_md.HINCRBY pk(sid), "retries", 1).to_i rescue 0
    #(redis.hset pk(sid), "status", "halted") if attempts > MaxRetries
  end

  def reset_retry(sid)
    redis_md.hset pk(sid), "retries", 0
  end

  def pk(sid)
    "#{SubsKey}:#{sid}"
  end

  def bar5s?(sid)
    (redis_md.hget pk(sid), "bar5s") == "on"
  end

end
