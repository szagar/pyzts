$: << "#{ENV['ZTS_HOME']}/etc"
require "zts_config"
require 'zts_constants'
require 'launchd_helper'

module RedisPosition
  include ZtsConstants
  require "redis"
  include LaunchdHelper
  
  extend self
  
  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end
  
  def next_id
    SN.next_pos_id
  end
    
  def pk(id)
    "pos:#{id}"
  end

  def create(args)
    puts "RedisPositoin#create  args=#{args}"
    id = args[:pos_id]
    redis.hmset pk(id), args.flatten
    redis.zadd "poz:#{args[:account]}", PosStatus[args[:status]], id 
  end
  
  def set(id, args)
    puts "RedisPositoin#set(#{id},#{args})"
    args.each do |k,v|
      puts "redis.hset #{pk(id)}, #{k}, #{v}"
      redis.hset pk(id), k, v
      if(k.eql?("status")) 
        puts "redis.zadd \"poz:#{account(id)}\", PosStatus[#{v}.to_sym], #{id}"
        redis.zadd "poz:#{account(id)}", PosStatus[v.to_sym], id
      end
    end
    redis.publish "position:update", args.merge(pos_id: id)
  end
  
  def get(id)
    Hash[(redis.hgetall pk(id)).map{|(k,v)| [k.to_sym,v]}]
  end
  
  def sec_id(id)
    redis.hget(pk(id), 'sec_id') || nil
  end

  def account(id)
    redis.hget(pk(id), 'account') || nil
  end

  def position_detail(id)
    get(id)
  end

  def open_positions(account)
    redis.zrangebyscore "poz:#{account}", PosStatus[:open], PosStatus[:open]
  end
end
