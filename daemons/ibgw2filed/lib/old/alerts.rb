$: << "#{ENV['ZTS_HOME']}/etc"
require "zts_config"
require "launchd_helper"

module Alerts
  include LaunchdHelper
  require "redis"
  
  extend self
  
  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    
  end
  
  def k(alert, sec_id)
    begin
      "pxalert:#{alert.downcase}:#{sec_id}"
    rescue => e
      lstderr "ERROR ERROR in Alerts#k(#{alert},#{sec_id})"
      lstderr "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end
  end
  
  def k_rev(alert_id)
    begin 
      "pxalert_rev:#{alert_id}"
    rescue => e
      lstderr "ERROR ERROR in Alerts#k_rev(#{alert_id})"
      lstderr "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end
  end
  
  def active_price_alerts_by_sec_id(sec_id)
    redis.keys "pxalert:*:#{sec_id}"
  end
  
  def to_human(alert_key)
    str = ""
    redis.zrangebyscore(alert_key, 0, "inf", withscores: true).each do |id,level|
      str += sprintf "%12s %12s\n",id,level
    end
    str
  end
  
  def add(alert, sec_id, ref_id, price)
    lstdout "Alerts#add: redis.zadd #{k(alert,sec_id)}, #{price}, #{ref_id}"
    redis.zadd k(alert,sec_id), price, ref_id
    lstdout "Alerts#add: redis.set #{k_rev(ref_id)}, #{k(alert,sec_id)}"
    redis.set k_rev(ref_id), k(alert,sec_id)
    count(alert, sec_id)
  end
  
  def rem(alert, sec_id, ref_id)
    lstdout "Alerts#rem: redis.zrem #{k(alert,sec_id)}, #{ref_id}"
    redis.zrem k(alert,sec_id), ref_id
    count(alert, sec_id)
  end
  
  def rem_by_alert_id(alert_id)
lstderr "Alerts#rem_by_alert_id: alert_set = k_rev(#{alert_id})"
    alert_set = redis.get k_rev(alert_id)
lstdout "Alerts#rem_by_alert_id: redis.zrem #{alert_set}, #{alert_id}"
    redis.zrem alert_set, alert_id
lstderr "Alerts#rem_by_alert_id:  redis.del #{k_rev(alert_id)}"
    redis.del k_rev(alert_id)
  end
  
  def triggered(sec_id, price)
    ref_ids = []
    active_price_alerts_by_sec_id(sec_id).each do |alert_key|
      trigger = alert_key[/pxalert:(.*):\d+/,1]
      #lstdout "Alerts#triggered: trigger=#{trigger}"
      case trigger
      when 'marketbelow'
        low = price
        high = 'inf'
      when 'marketabove'
        low = '-inf'
        high = price
      when 'pricebelow'
        low = '-inf'
        high = price
      when 'priceabove'
        low = price
        high = 'inf'
      else
        lstderr "Alert Trigger <#{alert} NOT KNOWN !!"
      end
      #lstdout "Alerts#triggered: ref_ids << redis.zrangebyscore(#{alert_key}, #{low}, #{high})"
      redis.zrangebyscore(alert_key, low, high).each do |ref_id|
        ref_ids << ref_id
        rem(trigger, sec_id, ref_id)
      end
    end
    ref_ids.flatten
  end
  
  def count (alert, sec_id)
    (redis.zrangebyscore k(alert,sec_id), "-inf", "inf").count
  end
end
