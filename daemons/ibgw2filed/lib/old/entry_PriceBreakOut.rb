require 'entry_base'
require 'launchd_helper'
require 'redis_helper'

class String
  def valid_float?
    true if Float self rescue false
  end
end

class EntryPriceBreakOut < EntryBase
  include LaunchdHelper
  include RedisHelper
  
  def initialize(options={})
    super self.class, options
    @name = self.class.to_s[/Entry(.*)/,1]
  end
  
  def add_entry(attributes)
    lstdout "#{__FILE__}(#__LINE__})add_entry(#{attributes})"
    entry = super   # @entries[entry.entry_id] = setup
    entry.entry_name = @name

    lstdout "#{__FILE__}(#__LINE__})add_entry: entry=#{entry}"

    req_md(entry.mkt, entry.sec_id)
    lstdout "EntryPriceBreakOut#add_setup config_breakout_alert(#{entry.to_human})"
    config_breakout_alert(entry)
    entry.entry_status = 'open'
    persist_entry(entry)
  end
  
  def load_entry(entry_id)
    entry_data = @redis.hgetall "entry:#{entry_id}"
    entry = EntryStruct.from_hash(entry_data)
  end

  def stop_adj(price)
    (price.to_f/25)*0.125  
  end  
  
  def stop_price(entry)
    case entry.action
    when 'buy'
      entry.bo_price = (SM.high(entry.sec_id) + stop_adj(SM.high(entry.sec_id)))
      entry.price ||= (entry.bo_price + stop_adj(SM.high(entry.sec_id)))
    when 'sell'
      entry.bo_price = (SM.low(entry.sec_id) - stop_adj(SM.low(entry.sec_id)))
      entry.price ||= (entry.bo_price - stop_adj(SM.low(entry.sec_id)))
    else
      lstderr "Action (#{entry.action}) NOT known"
    end
    entry.bo_price = entry.bo_price.to_f.round(2)
    entry.price = entry.price.to_f.round(2)
    lstdout "stop_price(setup_id=#{entry.setup_id}/entry_id=#{entry.entry_id})#{entry.ticker}:  bo_price=#{entry.bo_price}  price=#{entry.price}"
  end
  
  def config_breakout_alert(entry)
    lstdout "config_breakout_alert(#{entry})"
    #if %w[tt_swing tt_position].include?(entry.setup_src)
    if %w[Swing Position].include?(entry.trade_type)
      msg = { alert_px: entry.stop_price }
    else
      # use breakout price from setup if available, else calculate one
      entry.bo_price = entry.setup_trigger if (entry.setup_trigger and
                                               entry.setup_trigger.valid_float?)
      stop_price(entry) unless entry.preset_bo
      msg = { alert_px: entry.bo_price }
    end
    
    triggerMap = {'long' => 'MarketAbove', 'short' => 'MarketBelow'}
    trigger = triggerMap[entry.side]
    alert_id = persist_entry_alert(entry.entry_id)

    msg.merge!(ref_id: alert_id)
    msg.merge!(sec_id: entry.sec_id)
    msg.merge!(trigger: trigger)
    msg.merge!(action: 'add')

    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:price]
    lstdout "<-(#{@core_exchange.name}/#{routing_key}/#{msg[:ref_id]}) \"add\" #{msg[:ticker]}(#{msg[:sec_id]}) #{msg[:alert]} #{msg[:alert_px]})"
    @core_exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
  end
  
  def qualify?(setup)
    super
  end
  
  def watch_for_price_alerts(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:alert][:price]
    @amqp_channel.queue("", :auto_delete => true)
                 .bind(@core_exchange, :routing_key => routing_key)
                 .subscribe do |headers, payload|
      lstdout "->(#{@core_exchange.name}/#{headers.routing_key}/#{headers.message_id})"
      alert_id = headers.message_id
      if (entry_id = get_entry_alert(alert_id)) then
        entry = load_entry(entry_id)
        entry.entry_status = 'triggered'
        persist_entry(entry)
        update_setup_trigger_count(entry)
        
        lstdout "watch_for_price_alerts:#{name}:entry=#{entry}"
        lstdout "@send_entry.call(#{name},#{entry.to_human})"
        @send_entry.call(name,entry)
      end
    end
  end

  def subscriptions(channel)
    #logger.debug "watch_for_price_alerts(channel)"
    watch_for_price_alerts(channel)
  end
  
end
