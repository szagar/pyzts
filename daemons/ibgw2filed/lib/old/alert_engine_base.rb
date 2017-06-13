#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'screen'
require 'json'
require 'amqp'
require "zts_config"
require 'adminable'
require 'alerts'
require 'applescript'
require 'zts_logger'
require 'launchd_helper'

class AlertEngineBase
  include LaunchdHelper
  include Adminable
  include Alerts
  attr_accessor :exchange, :channel, :proc_name
  attr_accessor :logger
  
  def initialize(alert_name, alert_desc=nil)
    @alert_name = alert_name
    @proc_name = "alert_#{alert_name}"

    @logger = ZtsLogger.instance
    logger.set_proc_name(proc_name)
    
#    @alerts = Hash.new
#    @alerts.default = Array.new
#    @sec_list = Hash.new
#    @sec_list.default = 0
#    @triggers = Hash.new{|hash, key| hash[key] = Hash.new}
    
    set_hdr "Alert Engine: #{alert_name}           proc_name: #{proc_name}"
    set_hdr "Description: {alert_desc}" if alert_desc != nil
  end
  
  def clear
    write_hdr
  end
  
  def talk(msg)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:data][:voice]}"  
    exchange.publish(msg, :routing_key => routing_key)
  end
  
  def send_alert(ref_id)
    routing_key = ZtsApp::Config::ROUTE_KEY[:alert][:price]
    logger.info "<-(#{exchange.name}/#{routing_key}/#{ref_id}) #{ref_id}"
    lstdout "<-(#{exchange.name}/#{routing_key}/#{ref_id}) #{ref_id}"
    exchange.publish(ref_id, :routing_key => routing_key, :message_id => ref_id, :persistent => true)
    
  end
  
  def monitor_alerts
    trigger_map = { 'marketbelow' =>  'low',  'marketabove' =>  'high',
                    'pricebelow' =>   'high', 'priceabove' =>   'low' }
    
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:data][:bar5s]}.#"
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                                            ZtsApp::Config::EXCHANGE[:market][:options])
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      headers.routing_key[/md.bar.5sec\.(.*)\.(.*)/]
      mkt,sec_id = [$1, $2]
      bar = JSON.parse(payload)
      #price = (bar.fetch(trigger_map[trigger.downcase]){bar['wap']}).to_f
      price = bar['wap'].to_f
      Alerts.triggered(sec_id,price).each do |ref_id|
        lstdout "Alert Triggered: ref_id=#{ref_id}  sec_id=#{sec_id}"
        send_alert( ref_id )
        #remove_alert( {trigger: trigger, sec_id: sec_id, ref_id: ref_id} )
      end
      
#      triggers[sec_id].keys.each do |trigger|
#        price = (bar.fetch(trigger_map[trigger.downcase]){bar['wap']}).to_f
#        Alerts.triggered(sec_id, price).each do |ref_id|
#          lstdout "Alert Triggered: ref_id=#{ref_id}  sec_id=#{sec_id}"
#          send_alert( ref_id )
#          remove_alert( {trigger: trigger, sec_id: sec_id, ref_id: ref_id} )
#        end
#      end
    end
  end

#  pr = Proc.new (|px| { px <= price }

  def create_alert( parms )
    logger.debug "create_alert( #{parms} )"
    sec_id = parms[:sec_id]
    ref_id = parms[:ref_id]
    trigger = parms[:trigger]   # PriceBelow, PriceAbove, MarketAbove, MarketBelow
    price = parms[:price]

#    sec_list[sec_id] += 1

#    cnt = triggers[sec_id].fetch(trigger,0)
#    triggers[sec_id][trigger] = cnt + 1
#    puts "Alerts.rem(#{parms[:trigger]}, #{parms[:sec_id]}, #{parms[:ref_id]})"
#    Alerts.rem(parms[:trigger], parms[:sec_id], parms[:ref_id])
    lstdout "Alerts.add(#{trigger}, #{sec_id}, #{ref_id}, #{price})"
    logger.info "Alerts.add(#{trigger}, #{sec_id}, #{ref_id}, #{price})"
    Alerts.add(trigger, sec_id, ref_id, price)
    show_alerts_for_sec_id(sec_id, "triggers for sec_id: #{sec_id} -create_alert")
  end
  
  def show_alerts_for_sec_id(sec_id, title="triggers ....")
    lstdout "#{title}"
    Alerts.active_price_alerts_by_sec_id(sec_id).each do |alert|
      lstdout Alerts.to_human(alert)
    end
  end
  
  def remove_alert( parms )
    logger.debug "remove_alert(#{parms})"
    sec_id = parms[:sec_id]
    ref_id = parms[:ref_id]
    trigger = parms[:trigger]
    logger.info "remove_alert #{ref_id}(#{sec_id}) #{trigger}"

    show_alerts_for_sec_id(sec_id, "triggers for sec_id: #{sec_id} -remove_alert-1")
    
#    triggers[sec_id].fetch(trigger) { return }
    
    cnt = Alerts.rem(trigger, sec_id, ref_id)

#    triggers[sec_id][trigger] -= 1 if (cnt)

#    logger.debug "triggers[#{sec_id}].delete(#{trigger}) if (#{triggers[sec_id][trigger]} < 1)"
#    triggers[sec_id].delete(trigger) if (triggers[sec_id][trigger] < 1)
    
    show_alerts_for_sec_id(sec_id, "triggers for sec_id: #{sec_id} -remove_alert-2")
    
#    if (triggers[sec_id].empty?) then
#      logger.debug "triggers.delete(#{sec_id})"
#      triggers.delete(sec_id)
#
#      logger.debug "sec_list.delete(#{sec_id})"
#      sec_list.delete(sec_id)
#    end
  end
  
#  def watch_closed_positions
#    routing_key = ZtsApp::Config::ROUTE_KEY[:position][:closed]
#    set_hdr "exchange(#{exchange_mkt.name}) bind(#{routing_key})\n"
#    channel.queue("", :auto_delete => true).bind(exchange, :routing_key => routing_key).subscribe do |headers, payload|
#      rec = JSON.parse(payload)
#      logger.debug "->(#{routing_key}): #{rec}"
#      ref_id = rec['pos_id']
#      sec_id = rec['sec_id']
#      remove_alert( {sec_id: sec_id, ref_id: ref_id} )
#    end
#  end
  
  def config(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:price]
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload)
      lstdout "->(#{exchange.name}/#{headers.routing_key}/#{headers.message_id}): #{rec}"
      logger.info "->(#{exchange.name}/#{headers.routing_key}/#{headers.message_id}): (#{rec['sec_id']}) #{rec['action']} #{rec['alert']} #{rec['alert_px']}"
      if rec['action'].eql?("add")
        create_alert( {trigger: rec['trigger'], sec_id: rec['sec_id'], 
                        ref_id: rec['ref_id'], price: rec['alert_px']} )
      elsif rec['action'].eql?("rem")
        remove_alert( {trigger: rec['trigger'], sec_id: rec['sec_id'], ref_id: rec['ref_id']} )
      end
    end
  end
  
  def run
    EventMachine.run do
#      timer = EventMachine::PeriodicTimer.new(20) do
#        $stderr.puts "#{proc_name}: the time is #{Time.now}"
#      end
      
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
  
      @channel = AMQP::Channel.new(connection)
      @exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], ZtsApp::Config::EXCHANGE[:core][:options])
      
      logger.amqp_config(channel)
      watch_admin_messages(channel)
      config(channel)
      monitor_alerts
      
      Signal.trap("INT") { connection.close { EventMachine.stop } }
      clear
    end
  end
end
