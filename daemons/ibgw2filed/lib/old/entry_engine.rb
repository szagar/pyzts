$: << "#{ENV['ZTS_HOME']}/etc"

require 'stringio'
require 'zts_constants'
require 'zts_config'
require 'setup_struct'
require 'alert_mgr'
require 'alert_mgr_store'
require 'entry_proxy'
require 'last_value_cache'
require 's_m'

class NoSecIdException < StandardError; end
class SetupError       < StandardError; end
class SideNotKnown     < StandardError; end

class EntryEngine
  include ZtsConstants

  attr_accessor :alert_mgr

  def initialize
    @alert_mgr = AlertMgr.new(persister=AlertMgrStore.new)
    @lvc       = LastValueCache.instance

    @md_subscriptions      = Hash.new
    @descretionary_entries = Array.new
  end
  
  def elegible_entries(setup)
    if (setup.sec_id = SM.sec_lookup(setup.ticker)).nil?
      alert("entry_engine: SM.sec_lookup for =#{setup.ticker}= FAILED.")
      raise NoSecIdException.new, "EntryEngine#elegible_entries(#{setup.ticker})"
    end

    setup.setup_id = SN.next_setup_id.to_s

    entries = []
    entries = case setup.entry_signal
    when "engulfing_white", "dragon"
      tt1_setup(setup)
    when "pre-buy"
      pre_buy_setup(setup)
    when "descretionary"
      descretionary_setup(setup)
    else
      puts "entry_signal(#{setup.entry_signal}) not known"
      []
    end

    #entries.reject! {|e| valid_entry?(e) == false}

    entries
  rescue
    puts "setup error exception"
    {}
  end

  def setup_entries(setup)
    #puts "setup_entries(setup)"
    entries = Array.new
    Array(elegible_entries(setup)).each do |entry|
      #puts "setup_entries entry=>#{entry.dump}"
      case entry.entry_signal
      when 'engulfing_white', 'dragon'
        @md_subscriptions[setup.ticker] = true
        setup_alert_for_entry(entry.entry_id, entry.side,
                              entry.sec_id, entry.entry_stop_price)
      when 'pre-buy'
        @md_subscriptions[setup.ticker] = true
        entry.trailing_stop_type = "support"
        setup_alert_for_entry(entry.entry_id, entry.side,
                              entry.sec_id, entry.entry_stop_price)
      when 'descretionary'
        entries.push(entry)
      else
        alert "EntryEngine#setup_entries: entry_signal #{entry.entry_signal} NOT known"
      end
    end
    entries
  end

  def triggered(bar)
    alerts = @alert_mgr.triggered(bar)
    results = []
    #alerts = @alert_mgr.trigger_above(bar.sec_id, bar.high)
    alerts.each do |alert|
      alert.close
      results.push alert
    end
    #results = Array(@alert_mgr.trigger_above(bar.sec_id, bar.high))
    #results += @alert_mgr.trigger_below(bar.sec_id, bar.low)
    #while entry=descretionary_entries.pop
    #  @results.push(entry)
    #end
    results
  end
  
  def alerts(sec_id)
    @alert_mgr.list(sec_id)
  end

  def market_data_subscription?(ticker)
    @md_subscriptions[ticker]
  end

  ############
  private
  ############

  def valid_entry?(entry, transcript=StringIO.new)
    rtn = true
    unless entry.work_price && entry.work_price > 1.0
      transcript.puts "entry:#{entry.entry_id} bad work_price:#{entry.work_price}"
      rtn = false
    end
    unless entry.limit_price > entry.work_price
      transcript.puts "entry:#{entry.entry_id} bad limit_price:#{entry.limit_price}"
      rtn = false
    end
    unless %w(long short).include?(entry.side)
      transcript.puts "entry:#{entry.entry_id} unknown side:#{entry.side}"
      rtn = false
    end
    unless %w(engulfing_white dragon pre-buy descretionary).include?(entry.entry_signal)
      transcript.puts "entry:#{entry.entry_id} unknown entry_signal:#{entry.entry_signal}"
      rtn = false
    end
    rtn
  end

  def tt1_setup(setup)
    entries = []

    sidex = get_sidex(setup.side)
    work_price  = get_work_price(setup.side, setup.sec_id)
    stop_price  = calc_stop_from_work_price(work_price, setup.side)
    puts "limit_price = calc_limit_from_stop_price(#{stop_price}, #{setup.side})"
    limit_price = calc_limit_from_stop_price(stop_price, setup.side)
    puts "limit_price =#{limit_price}"

    swing_rr    = swing_rr(work_price, setup).round(2)
    position_rr = position_rr(work_price, setup).round(2)

    if swing_rr >= MIN_RTN_RISK
      entry = EntryProxy.new(setup.attributes)
      entry.trade_type         = "Swing"
      entry.trailing_stop_type = "support"
      entry.entry_stop_price   = stop_price
      entry.stop_loss_price    = setup.weak_support - sidex *
                                     ((work_price < 10.0) ? 0.12 : 0.25)
      entry.limit_price        = limit_price.round(2)
      entry.initial_risk       = (entry.limit_price - entry.stop_loss_price).abs
      #entry.entry_signal       = setup.entry_signal
puts "Swing trade: #{entry.dump}"
      entries << entry
    end

    if position_rr >= MIN_RTN_RISK
      entry = EntryProxy.new(setup.attributes)
      entry.trade_type         = "Position"
      entry.trailing_stop_type = "support"
      entry.entry_stop_price = stop_price
      entry.stop_loss_price  = stop_loss_from_support(setup.side,
                               setup.moderate_support, work_price)
      entry.stop_loss_price  = setup.moderate_support - sidex *
                                     ((work_price < 10.0) ? 0.12 : 0.25)
      entry.limit_price      = limit_price.round(2)
      entry.initial_risk     = (entry.limit_price - entry.stop_loss_price).abs
      #entry.entry_signal     = setup.entry_signal
puts "Position trade: #{entry.dump}"
      entries << entry
    end

    entries
  end

  def stop_loss_from_support(side, support_level, work_price)
    sidex = get_sidex(setup.side)
    entry.stop_loss_price  = support_level - sidex *
                             ((work_price < 10.0) ? 0.12 : 0.25)
  end

  def long_term_setup(setup)
    stop_price = setup.entry_stop_price
    work_price = get_work_price(setup.side, setup.sec_id)
    sidex      = get_sidex(setup.side)

    entry = EntryProxy.new(setup.attributes)
    entry.trailing_stop_type = "strong_support"
    entry.stop_loss_price    = setup.strong_support - sidex *
                                     ((work_price < 10.0) ? 0.12 : 0.25)
    entry.limit_price        = limit_price.round(2)
    entry.initial_risk = (entry.limit_price - entry.stop_loss_price).abs
    Array(entry)
  end

  def descretionary_setup(setup)
    entry = EntryProxy.new(setup.attributes)
    entry.trailing_stop_type = "support"
    entry.trailing_stop_type = "atr"
    work_price             = get_work_price(entry.side, entry.sec_id)
#puts "descretionary_setup work_price=#{work_price}"
    entry.entry_stop_price = (setup.entry_stop_price.is_a? Numeric) ? 
                                   setup.entry_stop_price :
                                   calc_stop_from_work_price(work_price, entry.side)
#puts "descretionary_setup entry.entry_stop_price=#{entry.entry_stop_price}"
    entry.limit_price = calc_limit_from_stop_price(entry.entry_stop_price, setup.side)
#puts "descretionary_setup entry.limit_price=#{entry.limit_price}"
    Array(entry)
  end

  def pre_buy_setup(setup)

    support = setup.attributes.fetch(:support) {
                   setup.attributes.fetch(:weak_support) {
                       raise SetupError }}

    sidex       = get_sidex(setup.side)
    work_price  = get_work_price(setup.side, setup.sec_id)
    stop_price  = setup.entry_stop_price
    limit_price = calc_limit_from_stop_price(stop_price, setup.side)

    entry = EntryProxy.new(setup.attributes)
    entry.trailing_stop_type = "support"
    entry.stop_loss_price    = setup.weak_support - sidex *
                                     ((work_price < 10.0) ? 0.12 : 0.25)
    entry.limit_price        = limit_price.round(2)
    #entry.entry_signal       = setup.entry_signal
    Array(entry)
  end

  def position_rr(work_price, setup)
    (setup.tgt_gain_pts < MIN_TGT_PT_GAIN) ? 0.0 :
                       (setup.tgt_gain_pts.to_f /
                          (work_price.to_f - setup.moderate_support.to_f))
  rescue
    0.0
  end

  def swing_rr(work_price, setup)
    (setup.avg_run_pt_gain < MIN_RUN_PTS) ? 0.0 :
                       (setup.avg_run_pt_gain.to_f /
                           (work_price.to_f - setup.weak_support.to_f))
  rescue
    0.0
  end

  def setup_alert_for_entry(entry_id, side, sec_id, entry_stop_price)
    if side == "long"
      market_above_alert(entry_id, sec_id, entry_stop_price)
    else
      market_below_alert(entry_id, sec_id, entry_stop_price)
    end
  end

  def market_above_alert(id, sec_id, level, one_shot=true)
    alert = AlertProxy.new(ref_id:   id,  sec_id: sec_id,
                           op:       :>=, level:  level,
                           one_shot: true                   )
    @alert_mgr.add_alert(alert)
  end

  def market_below_alert(id, sec_id, level, one_shot=true)
    @alert_mgr.add_alert(id, sec_id, :<=, level)
  end

  def get_work_price(side, sec_id)
    case side
    when "long"
      work_price  = @lvc.high(sec_id).to_f
    when "short"
      work_price  = @lvc.low(sec_id).to_f
    else
      alert "get_work_price: side(#{side}) not known"
    end
  end

  def get_sidex(side)
    sidex = case side
            when "long"
              1 
            when "short"
              -1
            else
              puts "get_sidexside(#{side}) not known"
            end
    sidex
  end

  def calc_limit_from_stop_price(stop_price, side)
    case side
    when "long"
      limit_price = stop_price + ((stop_price < 10) ?  0.25 : 0.375)
    when "short"
      limit_price = stop_price - ((stop_price < 10) ?  0.25 : 0.375)
    else
      alert "calc_limit_from_stop_price: side(#{side}) not known"
      raise SideNotKnown, "EntryEngine#calc_limit_from_stop_price"
    end
  end

  def calc_stop_from_work_price(work_price, side)
    case side
    when "long"
      stop_price = work_price + ((work_price < 10) ? 0.12 : 0.25)
    when "short"
      stop_price = work_price - ((work_price < 10) ? 0.12 : 0.25)
    else
      alert "calc_stop_from_work_price: side(#{side}) not known"
      raise SideNotKnown, "EntryEngine#calc_stop_from_work_price"
    end
  end

  def alert str
    puts str
  end
end

__END__

  def add_entry(entry)
    lstdout "add_entry #{entry.name}"
    @entries[entry.name] =  entry
  end

  def request_entry_config(channel)
    # request setup config
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:config][:entry]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], 
                             ZtsApp::Config::EXCHANGE[:core][:options])
    exchange.publish("", :routing_key => routing_key, :persistent => true)  
  end
  
  def config_entries(channel)
    @entries.each do |name,entry|
      lstdout "#{entry.name} config"
      entry.config(channel)
    end
    
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:config][:entry]}.#"
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      msg = JSON.parse(payload)
      lstdout "entries[#{msg['entry']}].add_setup_src(#{msg['setup_src']})"
      if(@entries[msg['entry']]) then
        @entries[msg['entry']].add_setup_src(msg['setup_src'])
        @setup_src_list[msg['setup_src']] = true
      else
        lstderr "Entry #{msg['entry']} NOT configured"
      end
    end
  end

  def watch_for_setups(channel)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:entry][:default]}.#"
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    lstdout "subscribe to #{routing_key}"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      setup = SetupStruct.from_hash(JSON.parse(payload))
      lstdout "->(#{exchange.name}/#{headers.routing_key}) #{setup.to_human}"
      
      if(setup.tod) then
        lstdout "config_tod_alert(channel, setup)"
        config_tod_alert(channel, setup)
      else
        config_entry(setup)
      end
    end
  end
  
  def config_tod_alert(channel, setup)
    alert_id = persist_tod_alert(setup.setup_id)
    #alert_id = SN.next_tod_alert_id

    #@pending_list[alert_id.to_s] = setup.setup_id
    
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:time]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    msg = {src: @proc_name, ref_id: alert_id, tod: setup.tod}
    lstdout "<-(#{exchange.name}/#{routing_key}) #{msg}"
    exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
  end
  
  def watch_for_alerts(channel)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:alert][:time]}.#{@proc_name}"
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    set_hdr "(#{exchange.name}/#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      lstdout "->(#{exchange.name}/#{headers.routing_key}) #{payload.inspect}"
      rec = JSON.parse(payload, symbolize_names: true)
      alert_id = rec[:ref_id]
      setup_id = get_tod_alert(alert_id)
      #setup_id = @pending_list[alert_id]
      setup = SetupStruct.from_hash(redis_get_setup(setup_id))
      #@pending_list.delete(alert_id)  { |id| lstderr "#{id} not found for alert";false}
      if (setup) then
        config_entry(setup)
      else
        lstderr "Setup(#{alert_id}) Not Found in redis.entry_alerts"
      end
    end
  end
  
  def watch_for_config_requests(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:config][:setup]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    set_hdr "(#{exchange.name}/#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      push_config
    end
  end
  
  def config_entry(setup)
    lstdout "config_entry(#{setup})"
    @entries.each do |name,entry|
      lstdout "name=#{name}  entry=#{entry}"
      next unless entry.qualify?(setup)
      lstdout "entry.add_entry(#{setup.attributes})"
      entry.add_entry(setup.attributes)
      setup.pending_entries = (setup.pending_entries || 0).to_i + 1
      setup.triggered_entries ||= 0
      persist_setup(setup)
    end
  end
  
  def info
    @entries.each do |name,entry|
      lstdout "Entry: #{name}"
#      entry.entries.each do |id,setup|
#        logger.debug "    - #{id}/#{setup.setup_id} #{setup.ticker}(#{setup.sec_id})   #{setup.triggered_entries}/#{setup.pending_entries}"
#      end
    end
  end
  
  def publish_config(src)
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:setup]
    lstdout "<-(#{exchange.name})/#{routing_key}) setup: #{src}, entry: #{entry_name}"
    exchange.publish({setup: src, entry: entry_name}.to_json, :routing_key => routing_key)
  end
  
  def push_config
    @setup_src_list.each do |src,value|
      publish_config(src)
    end
  end
  
  def run
    EventMachine.run do
      lstdout "connection = AMQP.connect(host: #{ZtsApp::Config::AMQP[:host]})"
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
  
      channel = AMQP::Channel.new(connection)
      
      logger.amqp_config(channel)

      config_entries(channel)
      request_entry_config(channel)
      info

      watch_admin_messages(channel)
      watch_for_alerts(channel)
      watch_for_setups(channel)
      watch_for_config_requests(channel)
      
#      EM.add_periodic_timer(60) do
#        info
##        connection.close { EventMachine.stop }
#      end
  
    end
  end
end
