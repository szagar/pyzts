#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'my_signal'
require 'set'

require 'screen'
require 'json'
require 'amqp'
require 'zts_config'
require 'adminable'
require 'zts_logger'
require 'launchd_helper'
require 'redis_helper'

class SignalEngine
  include LaunchdHelper
  include RedisHelper
  include Adminable
  attr_accessor :exchange, :exchange_mkt, :channel
  attr_accessor :proc_name, :positions
  attr_accessor :logger    #, :sec_ids, :signals
  
  def initialize(signal_name, signal_desc=nil)
    @signal_name = signal_name
    @proc_name = "signal_#{signal_name}"

    @logger = ZtsLogger.instance
    logger.set_proc_name(proc_name)
    
    #@sec_ids = Set.new
    #@signals = Hash.new
    
    set_hdr "Signal Engine: #{signal_name}           proc_name: #{proc_name}"
    set_hdr "Description: #{signal_desc}" if signal_desc != nil    
  end
  
  def show_after_header_hook
    show_signals
  end
  
  def signal_trader(parms)
    message = parms
    routing_key = ZtsApp::Config::ROUTE_KEY[:signal][:exit][:stop]
    logger.info "<-EXIT(#{exchange.name}/#{routing_key}): #{message}, :persistent => true"
    lstdout"<-EXIT(#{exchange.name}/#{routing_key}): #{message}"
    exchange.publish(message.to_json, :routing_key => routing_key, :persistent => true)
  end
  
  def signal_trader_eod(pos_id, desc="day trade EOD exit")
    msg = {pos_id: pos_id, desc: desc}
    routing_key = ZtsApp::Config::ROUTE_KEY[:signal][:exit][:eod]
    logger.info "<-EXIT/eod(#{exchange.name}/#{routing_key}): #{msg}, :persistent => true"
    lstdout "<-EXIT/eod(#{exchange.name}/#{routing_key}): #{msg}"
    exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)    
  end
  
#  def monitor_signals(channel)
#    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:data][:bar5s]}.#"
#    set_hdr "exchange(#{exchange_mkt.name}) bind(#{routing_key})\n"
#    channel.queue("", :auto_delete => true).bind(exchange_mkt, :routing_key => routing_key).subscribe do |headers, payload|
#      headers.routing_key[/md.bar.5sec\.(.*)\.(.*)/]
#      mkt,sec_id = [$1, $2.to_s]
#
#      #next unless sec_ids.include?(sec_id)
#      next unless (@signals[sec_id] && @signals[sec_id].size > 0)
#      bar = JSON.parse(payload)
#      #puts "#{bar['open']} / #{bar['high']}-#{bar['low']} / #{bar['close']} wap #{bar['wap']}"
#      
#      @signals[sec_id].each do |sig|
#        if sig.active && sig.check_bar(bar) then
#          message = {sec_id: sec_id, pos_id: sig.ref_id, mkt: :stock, desc: sig.desc}
#          lstdout "Signal Hit! #{message}"
#          signal_trader(message)
#          sig.active = false
#        end
#      end
#    end
#  end
  
  def watch_for_price_alerts(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:alert][:price]
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      lstdout "->(#{exchange.name}/#{headers.routing_key}/#{headers.message_id})"
      alert_id = headers.message_id
      if (pos_id = get_exit_alert(alert_id)) then
        message = {pos_id: pos_id, desc: "stop loss exit"}
        lstdout "Signal Hit! #{message}"
        signal_trader(message)
      end
    end
  end
  
  def watch_for_time_alerts(channel)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:alert][:time]}.#{proc_name}"
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      logger.info "debug1: ->(#{exchange.name}/#{headers.routing_key}) #{payload.inspect}"
      rec = JSON.parse(payload, symbolize_names: true)
      alert_id = rec[:ref_id]
      pos_id = get_tod_alert(alert_id)
      lstdout "->(#{exchange.name}/#{headers.routing_key}) #{pos_id}"
      logger.info "->(#{exchange.name}/#{headers.routing_key}) #{pos_id}"
      
      signal_trader_eod(pos_id)
    end
  end
  
  def watch_closed_positions(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:position][:closed]
    set_hdr "exchange(#{exchange_mkt.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload)
      logger.info "watch_closed_positions: #{rec}"
      lstdout "->(#{headers.routing_key}): #{rec}"
      pos_id = rec['pos_id']
      sec_id = rec['sec_id']
#      remove_position_signals(pos_id)
      remove_exit_alerts(pos_id)
    end
  end
  
#  def request_stops_for_open_positions
#    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:spin][:stop]
#    ["long","short"].each do |side|
#      logger.info "<-#{exchange.name}.publish(side, :routing_key => #{routing_key}, :persistent => true)"
#      exchange.publish(side, :routing_key => routing_key)
#    end
#  end

  def show_signals
  end
    
#  def create_stop_signal( parms )
#    lstdout "create_stop_signal(#{parms})"
#    logger.info "create_stop_signal(#{parms})"
#    sec_id = parms[:sec_id]
#    ref_id = parms[:ref_id]
#    var = parms[:var]
#    level = parms[:level]
#    op = parms[:op].to_sym
#    
#    lstdout "create_stop_signal: #{ref_id}(#{sec_id}) #{var} #{op} #{level}"
#    
#    @signals.fetch(sec_id) { |sid| logger.info "@signals[#{sid}] = []";@signals[sid] = [] }
#    @signals[sec_id].push MySignal.new(ref_id: ref_id, variable: var, level: level, operator: op)
#    lstdout "@signals[#{sec_id}].size = #{@signals[sec_id].size}"
#    #sec_ids.add(sec_id.to_s)
#    lstdout "Signals ...."
#    @signals.each do |k,v|
#      v.each do |s|
#        lstdout s
#      end
#    end
#  end
  
#  def config_price_alert(parms)
#    lstderr "SignalEngine#config_price_alert(#{parms})"
#    triggerMap = {'long' => 'MarketAbove', 'short' => 'MarketBelow'}
#    trigger = triggerMap[parms[:side]]
#    alert_id = persist_exit_alert(parms[:pos_id])
#    msg = {ref_id: alert_id, sec_id: parms[:sec_id],  
#           alert_px: parms[:level], trigger: trigger, action: "add"}
#
#    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:price]
#    lstdout "<-(#{exchange.name}/#{routing_key}/#{msg[:ref_id]}) \"add\" #{msg}"
#    exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
#  end
  
  def config_tod_alert(pos_id, tod)
    alert_id = persist_tod_alert(pos_id)
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:time]    
    msg = {src: proc_name, ref_id: alert_id, tod: tod}
    
    lstdout "<-(#{exchange.name}/#{routing_key}) #{msg}"
    logger.info "<-(#{exchange.name}/#{routing_key}) #{msg}"
    exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
  end
  
  def config(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:signal][:tod]
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    lstdout "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload, :symbolize_names => true)
      lstderr "->(#{headers.routing_key}): #{rec}"
      lstdout "->(#{headers.routing_key}): #{rec}"
      logger.debug "->(#{headers.routing_key}): #{rec}"
      config_tod_alert(rec[:pos_id], rec[:tod])
    end
    
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:signal][:longstop]
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload, :symbolize_names => true)
      lstdout "->(#{headers.routing_key}): #{rec}"
      logger.info "->(#{headers.routing_key}): #{rec}"
#      var = rec[:var] || (rec[:side].eql?('long') ? :low : :high)
#      op = rec[:op] || (rec[:side].eql?('long') ? :<= : :>=)
      
      triggerMap = {'long' => 'MarketBelow', 'short' => 'MarketAbove'}
      trigger = triggerMap[rec[:side]]
      alert_id = persist_exit_alert(rec[:pos_id])
      msg = {ref_id: alert_id, sec_id: rec[:sec_id],  
             alert_px: rec[:stop_px], trigger: trigger, action: "add"}

      routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:price]
      lstdout "<-(#{exchange.name}/#{routing_key}/#{msg[:ref_id]}) \"add\" #{msg}"
      exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
  
    end
  end
  
#  def remove_position_signals(pos_id)
#    lstdout "remove_signal(#{ref_id}) sec_id=#{sec_id}"
#    logger.info "remove_signal(#{ref_id}) sec_id=#{sec_id}"
#    @signals[sec_id].delete_if { |s| s.ref_id.to_i == ref_id.to_i } if @signals[sec_id]
#    lstdout "remove_signal(#{ref_id}): @signals[#{sec_id}].size = #{@signals[sec_id].size}"
#    #sec_ids.delete(sid) if (signals[sid].size == 0)
#    msg = {ref_id: ref_id, sec_id: sec_id,  
#           trigger: alert, action: "rem"}
#
#    lstdout "<-(#{@core_exchange.name}/#{routing_key}/#{msg[:ref_id]}) \"add\" #{msg}"
#    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:price]
#    @core_exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
#
#  end
  
  def run
    EventMachine.run do
#      timer = EventMachine::PeriodicTimer.new(20) do
#        $stderr.puts "#{proc_name}: the time is #{Time.now}"
#      end
      
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
  
      @channel = AMQP::Channel.new(connection)
    #  channel.prefetch(1)
  
      @exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], ZtsApp::Config::EXCHANGE[:core][:options])
      @exchange_mkt = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name], ZtsApp::Config::EXCHANGE[:market][:options])
      
      logger.amqp_config(channel)
      watch_admin_messages(channel)
      config(channel)
      
#      monitor_signals(channel)
      watch_for_price_alerts(channel)
      watch_for_time_alerts(channel)
      watch_closed_positions(channel)
      #request_stops_for_open_positions
      
      write_hdr
      Signal.trap("INT") { connection.close { EventMachine.stop } }
    end
  end
end
