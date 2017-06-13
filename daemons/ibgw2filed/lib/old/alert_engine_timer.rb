#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'screen'
require 'json'
require 'amqp'
require "zts_config"
require 'adminable'
# smz below not needed ?
require 'alerts'
require 'zts_logger'
require 'time'
require 'time_alert'
require 'launchd_helper'

class AlertEngineTimer
  include LaunchdHelper
  include Adminable
  include Alerts
  include TimeAlert
  attr_accessor :exchange, :exchange_mkt, :channel, :alerts, :proc_name, :sec_list
  attr_accessor :triggers, :logger, :tod_alerts
  
  def initialize(alert_name, alert_desc=nil)
    @alert_name = alert_name
    @proc_name = "alert_#{alert_name}"

    @tod_alerts = Hash.new
    
    @logger = ZtsLogger.instance
    logger.set_proc_name(proc_name)
    
    @alerts = Hash.new
    @alerts.default = Array.new
#    @triggers = Hash.new{|hash, key| hash[key] = Hash.new}
    
    set_hdr "Timer Alert Engine: #{alert_name}           proc_name: #{proc_name}"
    set_hdr "Description: {alert_desc}" if alert_desc != nil
  end
  
  def clear
    write_hdr
  end
  
  def send_alert(routing_key, msg)
    lstdout "<-#{exchange.name}/#{routing_key}(#{msg})"
    logger.info "<-#{exchange.name}/#{routing_key}(#{msg})"
    exchange.publish(msg.to_json, :routing_key => routing_key, :persistent => true)
  end
  
  def monitor_alerts
  end

#  def remove_alert( parms )
#    logger.debug "remove_alert(#{parms})"
#    TimeAlert.rem()
#  end
  
  def add_tod_alert(src, ref_id, tod)
    begin
      route_name = "#{ZtsApp::Config::ROUTE_KEY[:alert][:time]}.#{src}"
      tod_alert_id = TimeAlert.add(ref_id, tod, route_name)
    
      secs = (Time.parse(tod).to_i - Time.now.to_i)
      
      raise(TimeCalcError, "Trigger Time in past") unless secs > 0
      EM.add_timer(secs) do
        send_alert(route_name, TimeAlert.msg(tod_alert_id))
        TimeAlert.rem(tod_alert_id)
      end
    rescue => e
      lstderr "Could not create tod event for #{ref_id}/#{tod}"
      logger.warn "Could not create tod event for  #{ref_id}/#{tod}"
      return "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end
  end
  
  def config(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:alert][:time]
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload)
      ref_id = rec['ref_id']
      tod = rec['tod']
      src = rec['src']
      lstdout "->(#{exchange.name}/#{headers.routing_key}/#{headers.message_id}): #{rec.inspect}"
      logger.info "->(#{exchange.name}/#{headers.routing_key}/#{headers.message_id}): #{rec.inspect}"
      add_tod_alert(src, ref_id, tod)
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
      @exchange_mkt = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name], ZtsApp::Config::EXCHANGE[:market][:options])
      
      logger.amqp_config(channel)
      watch_admin_messages(channel)
      config(channel)
      
      Signal.trap("INT") { connection.close { EventMachine.stop } }
      clear
    end
  end
end
