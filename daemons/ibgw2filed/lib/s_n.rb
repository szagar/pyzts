require "my_config"
require "store_mixin"
#require "redis_factory"
require "log_helper"
require "singleton"

class SN
  include LogHelper
  include Singleton
  include Store

  #attr_reader :redis

  def initialize
    #show_info "SN#initialize"
    Zts.configure do |config|
      config.setup
    end
    #@redis = RedisFactory2.new.client
  end

  def next_order_id
    redis.incr "seq:order_id"
  end
  
  def next_pos_id
    redis.incr "seq:pos_id"
  end
  
  def next_sec_id
    redis_md.incr "seq:sec_id"
  end

  def next_account_id
    redis.incr "seq:account_id"
  end

  def next_index_id
    redis.incr "seq:index_id"
  end
  
  def next_acct_pos_id
    redis.incr "seq:acct_pos_id"
  end
  
  def next_setup_id
    redis.incr "seq:setup_id"
  end

  def next_entry_id
    redis.incr "seq:entry_id"
  end
  
  def next_alert_id
    id = redis.incr "seq:alert_id"
    id.to_s
  end

  def next_alert_mgr_id
    redis.incr "seq:alert_mgr_id"
  end

  def next_tod_alert_id
    redis.incr "seq:tod_alert_id"
  end
      
  def next_alloc_id
    redis.incr "seq:alloc_id"
  end
      
  def next_xact_id
    redis.incr "seq:xact_id"
  end
      
  def last_xact_id
    redis.get "seq:xact_id"
  end
end
