require 'redis'
require 's_n'
#require_relative 'alerts'
require 'zts_constants'
require 'time'
require 'entry_struct'
require 'account_mgr'

module RedisHelper
  include ZtsConstants
  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end
  
  def persist_setup(setup)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    @redis.hmset "setup:#{setup.setup_id}", setup.attributes.flatten
    secs = (Time.parse("15:30").to_i - Time.now.to_i)
    @redis.expire "setup:#{setup.setup_id}", secs
  end

  def persist_order(order)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    order_id = SN.next_order_id.to_s
    order.order_id = order_id
    @redis.hmset "order:#{order_id}", order.attributes.flatten
    order_id
  end

  def persist_exit(exit)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    @redis.hmset "exit:#{exit.order_id}", exit.attributes.flatten
  end
  
  def persist_tod_alert(setup_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    alert_id = SN.next_tod_alert_id.to_s
    @redis.set "entry_alerts:#{alert_id}", setup_id
    alert_id
  end
  
  def get_tod_alert(alert_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    id = @redis.get "entry_alerts:#{alert_id}"
    @redis.del "entry_alerts:#{alert_id}"
    id
  end
  
  def persist_rmgr_alert(pos_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    alert_id = SN.next_alert_id.to_s
    @redis.set "rmgr_alert:#{alert_id}", pos_id
    @redis.set("rmgr_alert_rev:#{pos_id}", (redis.get("rmgr_alert_rev:#{pos_id}")+"," rescue "")+alert_id)
    alert_id
  end
  
  def get_rmgr_alert(alert_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    id = @redis.get "rmgr_alert:#{alert_id}"
    @redis.del "rmgr_alert:#{alert_id}"
    id
  end
  
  def remove_rmgr_alert(pos_id)
  end
  
  def persist_entry_alert(entry_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    alert_id = SN.next_alert_id.to_s
    @redis.set "bo_alert:#{alert_id}", entry_id
    alert_id
  end
  
  def get_entry_alert(alert_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    id = @redis.get "bo_alert:#{alert_id}"
    @redis.del "bo_alert:#{alert_id}"
    id
  end

  def persist_exit_alert(pos_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    alert_id = SN.next_alert_id.to_s
    @redis.set "exit_alert:#{alert_id}", pos_id
    @redis.set("exit_alert_rev:#{pos_id}", (redis.get("exit_alert_rev:#{pos_id}")+"," rescue "")+alert_id)
    alert_id
  end
  
  def get_exit_alert(alert_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    id = @redis.get "exit_alert:#{alert_id}"
    @redis.del "exit_alert:#{alert_id}"
    id
  end
    
#  def remove_exit_alerts(pos_id)
#    exit_alerts_for_pos_id(pos_id).split(',').each do |ref_id|
#      @redis.del "exit_alert:#{ref_id}" 
#      Alerts.rem_by_alert_id(ref_id)
#    end
#    @redis.del "exit_alert_rev:#{pos_id}" 
#  end

  def redis_get_setup(setup_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    @redis.hgetall "setup:#{setup_id}"
  end
  
  def remove_position_alerts(pos_id)
    remove_rmgr_alert(pos_id)
    remove_exit_alerts(pos_id)
  end

  def entry_list
    entries = []
    entries = redis.keys("entry:*").collect { |k|
      EntryStruct.from_hash(redis.hgetall(k))
    } 
    entries
  end

  def account_list
    AccountMgr.new.accounts
    #@redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    #redis.keys("account:*").map { |a| a[/account:(\w*)/,1] }.uniq.sort
  end

  private

  def exit_alerts_for_pos_id(pos_id)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    @redis.get("exit_alert_rev:#{pos_id}") || ""
  end
  
  def open_positions(account)
    puts "redis.zrangebyscore poz:#{account}, #{PosStatus[:open]}, #{PosStatus[:open]}"
    redis.zrangebyscore "poz:#{account}", PosStatus[:open], PosStatus[:open]
  end
  
  def setups_list_of_tickers
    tkrs = {}
    setup_list = redis.keys("setup:*").map { |s| s[/(setup:\w*)/,1] }.uniq.sort
    setup_list.each do |setup|
      tkrs[redis.hget(setup,'ticker')] = true
    end
    tkrs
  end

  def setups_list_of_sec_ids
    secs = {}
    setup_list = redis.keys("setup:*").map { |s| s[/(setup:\w*)/,1] }.uniq.sort
    setup_list.each do |setup|
      secs[redis.hget(setup,'sec_id')] = true
    end
    secs.keys
  end
  
  def account_status(acct_name)
    redis.hget("account:#{acct_name}", "status") || "unknown"
  end
end
