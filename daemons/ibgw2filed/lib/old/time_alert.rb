$: << "#{ENV['ZTS_HOME']}/etc"
require "zts_config"
require "s_n"

module TimeAlert
  require "redis"
  
  extend self
  
  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    
  end
  
  def k(tod_alert_id)
    begin
      "todAlert:#{tod_alert_id}"
    rescue 
      puts "ERROR ERROR in TimeAlert#k"
    end
  end
  
  def add(ref_id, tod, route_name)
    tod_alert_id = SN.next_tod_alert_id
    redis.hset k(tod_alert_id), 'ref_id', ref_id
    redis.hset k(tod_alert_id), 'tod', tod
    redis.hset k(tod_alert_id), 'route_name', route_name
    tod_alert_id
  end
  
  def rem(tod_alert_id)
    redis.del k(tod_alert_id)
  end
  
  def msg(tod_alert_id)
    ref_id = redis.hget k(tod_alert_id), 'ref_id'
    tod = redis.hget k(tod_alert_id), 'tod'
    {tod_alert_id: tod_alert_id, ref_id: ref_id, tod: tod}
  end
  
  def route(tod_alert_id)
    redis.hget k(tod_alert_id), 'route_name'
  end
  end
