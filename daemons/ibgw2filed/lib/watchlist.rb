#!/usr/bin/env ruby

require "file_helper"
#require "redis_factory"
require "store_mixin"

class Watchlist
  include Store

  def initialize(name)
    @name = name
    @rkey = "watchlist:#{@name}"
  end

  def is_member?(tkr)
    redis_md.sismember pk, tkr
  end

=begin
  def self.list(type="*")
    if type == "mca"
      result = mca_list
puts "result=#{result}"
result
    else
      (md_redis.keys "watchlist:#{type}").map { |k| k[/watchlist:(.*)/,1] }
    end
  end
=end

  def is_member?(tkr)
    redis_md.sismember @rkey, tkr
  end

  def components
    (redis_md.smembers @rkey).sort
  end

  def clear_watchlist
    redis_md.del @rkey
  end

  def add(tkr)
    (redis_md.sadd @rkey, tkr) unless tkr == ""
  end

  def rm(tkr)
    redis_md.srem @rkey, tkr
  end

  def mca
    redis_md.get "mca:#{@name}:last"
  end

  private

  def self.pk
    "watchlist:#{@name}"
  end

=begin
  def @md_redis
    #@redis_factory ||= RedisFactory.instance
    #@redis ||= @redis_factory.client("mkt_data")
    @md_redis ||= redis_md
  end

  def self.md_redis
    #redis_factory ||= RedisFactory.instance
    #redis ||= redis_factory.client("mkt_data")
    #@md_redis ||= redis_md
    redis_md
  end

  def self.mca_list
    redis_md.lrange "watchlist:mca", 0, -1
  end
=end
end

