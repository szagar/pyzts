$: << "#{ENV['ZTS_HOME']}/lib"
require "store_mixin"
#require "redis_factory"
require "s_n"
require 'alert_proxy'
require 'log_helper'

class AlertMgrStore # < RedisStore
  include LogHelper
  include Store

  attr_reader :sequencer

  def initialize
    #debug "AlertMgrStore#initialize"
    @sequencer = SN.instance
    super
  end

  def whoami
    self.class.to_s
  end

  def add_alert(src, ref_id, alert)
    debug "AlertMgrStore#add_alert(#{src}, #{ref_id}, #{alert})"
    debug "result = redis.sadd #{pk(src, ref_id)}, #{alert.alert_id}"
    redis.sadd pk(src, ref_id), alert.alert_id
  end

  def rm_alert(alert)
    redis.srem pk(alert.sec_id), alert.alert_id
  end

  def alerts(src, sec_id, ref_id, override=false)
    #debug "alerts(#{src}, #{sec_id}, #{ref_id}, #{override})"
    #debug "ids = (redis.smembers #{pk(src, sec_id)})"
    ids = (redis.smembers pk(src, sec_id))
    #debug "AlertMgrStore#alerts: ids=#{ids}"                 # ids=["1", "2", "3"]
    results = ids.each_with_object([]) { |alert_id,a| 
      h = (redis.hgetall "alert:#{alert_id}")
      a << AlertProxy.new(h) if ((h["ref_id"] == ref_id || ref_id == "*") && (override || h["status"] == "open"))
    }
    results
  end

  def adj_position_alert_levels(src,sec_id,pos_id,ratio)
    ids = (redis.smembers pk(src, sec_id))
puts "ids=#{ids}"
    results = ids.each do |alert_id|
      h = (redis.hgetall "alert:#{alert_id}")
puts "hh = #{h}"
puts "#{h["ref_id"]}/#{h["ref_id"].class} == #{pos_id}/#{pos_id.class}"
      if ((h["ref_id"] == pos_id || pos_id == "*") && (h["status"] == "open"))
        puts "redis.hset alert:#{alert_id}, level, #{h["level"].to_f * ratio.to_f}"
        redis.hset "alert:#{alert_id}", "level", h["level"].to_f * ratio.to_f
      end
    end
  end

  def exists?(src,id)
    redis.keys pk(src,id)
  end

  def check_then_delete(src)           # src = "EntryEngine"
    debug "AlertMgrStore#check_then_delete(#{src})"
    src_keys(src).each do |key_string|
      check_then_delete_key(key_string)
    end
  end

  def entry_exists?(entry_id)
    debug "AlertMgrStore#entry_exists?: (redis.keys entry:#{entry_id}).size > 0"
    (redis.keys "entry:#{entry_id}").size > 0
  end

  #######
  private
  #######

  #def redis
  #  $redis ||= RedisFactory2.new.client
  #end

  def next_id
    sequencer.next_alert_mgr_id
  end

  def pk(src, ref_id)
    "alert_mgr:#{src}:#{ref_id}"
  end

  def src_keys(src)
    redis.keys pk(src,"*")
  end

  def delete_closed(alert_id)
    # return true if alert is deleted
    debug "AlertMgrStore#delete_closed(#{alert_id})"
    redis.del "alert:#{alert_id}" if closed?(alert_id)
  end

  def orphaned_entry(alert_id)
    # return true if alert is deleted
    debug "AlertMgrStore#orphaned_entry(#{alert_id})"
    ref_id = alert_ref_id(alert_id)
    redis.del "alert:#{alert_id}" unless entry_exists?(ref_id)
    !entry_exists?(ref_id)
  end

  def closed?(alert_id)
    alert_status(alert_id) == "closed"
  end

  def alert_ref_id(alert_id)
    redis.hget "alert:#{alert_id}", "ref_id"
  end

  def alert_status(alert_id)
    redis.hget "alert:#{alert_id}", "status"
  end

  def check_then_delete_key(key_string)
    debug "AlertMgrStore#check_then_delete_key(#{key_string})"
#<<<<<<< HEAD
#    entity = (key_string =~ /EntryEngine/ ? "entry" : "DNK")
#    show_info "(redis.smembers #{key_string}).each_with_object([]) { |alert_id,a| "
#    (redis.smembers key_string).each_with_object([]) { |alert_id,a| 
#      # delete alert:<alert_id> if status == closed
#      redis.srem(key_string, alert_id) if delete_closed(alert_id)
#      # delete alert:<alert_id> unless entry:<ref_id> exists
#      redis.srem(key_string, alert_id) if delete_orphaned(entity,alert_id)
#=======
    delete_closed_alerts(key_string)
    delete_orphaned_entries(key_string) if key_string =~ /EntryEngine/
    #entity = (key_string =~ /EntryEngine/ ? "entry" : "DNK")
    #(redis.smembers key_string).each_with_object([]) { |alert_id,a| 
    #  redis.srem(key_string, alert_id) if delete_closed(alert_id)               # delete alert:<alert_id> if status == closed
    #  redis.srem(key_string, alert_id) if (entity == "entry" && orphaned_entry(entity,alert_id))
    #}
  end

  def  delete_orphaned_entries(key_string)
    debug "AlertMgrStore#delete_orphaned_entries(#{key_string})"
    debug "(redis.smembers #{key_string}).each { |alert_id| "
    (redis.smembers key_string).each { |alert_id| 
      redis.srem(key_string, alert_id) if orphaned_entry(alert_id)
    }
  end

  def delete_closed_alerts(key_string)
    debug "AlertMgrStore#delete_closed_alerts(#{key_string})"
    debug "(redis.smembers #{key_string}).each { |alert_id| "
    (redis.smembers key_string).each { |alert_id| 
      redis.srem(key_string, alert_id) if delete_closed(alert_id)
    }
  end
end
