#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'screen'
require 'json'
require 'amqp'
require 'account_proxy'
require_relative 'old/position'
require 'entry_struct'
#require 'order_struct'
require 'zts_config'
require 'adminable'
require 'zts_logger'
require 'launchd_helper'

class PmPortfMgr
  include LaunchdHelper
  include Adminable
  attr_accessor :account_name, :account, :account_id, :exchange, :money_mgr, :proc_name
  attr_accessor :logger
  
  def initialize( account_name )
    @account_name = account_name
    @proc_name = "pm_#{account_name}"
    
    @logger = ZtsLogger.instance
    logger.set_proc_name(proc_name)
    
    @account = AccountProxy.new(account_name)
    @account_id = account.account_id
    @money_mgr = account.money_mgr
    
    set_hdr "Portfolio Manager for account: #{account_name}\n"
    set_hdr "                      proc_name :: #{proc_name}\n"
  end
  
  def set_proc_name( proc_name )
    @proc_name = proc_name
    logger.set_proc_name(proc_name)
  end
  
  def clear
    write_hdr
  end
  
  def publish_config(account_name, setup, entry)
    logger.debug "publish_config money_mgr=#{money_mgr}", account_name
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:config][:money_mgr]}.#{money_mgr}"
    msg = {account: account_name, setup: setup, entry: entry}
    logger.debug "<-(#{exchange.name}/#{routing_key}): "\
                 "#{msg[:account]} #{msg[:setup]}/#{msg[:entry]}", account_name
    exchange.publish(msg.to_json, :routing_key => routing_key)
  end
  
  def push_config
    config
  end
  
  def config
    @money_mgr = account.money_mgr
    logger.debug "config money_mgr=#{money_mgr}", account_name
    account.setups.each do |set_ent|
      set_hdr "setup(#{account_name})  #{set_ent}}\n"
      setup, entry = set_ent.split("::")
      publish_config(account_name, setup, entry)
    end
  end
  
  def new_position(trade)
    pos = PositionProxy.new(trade.attributes
    lstdout "New position(#{pos.pos_id}) #{trade[:ticker]}/#{trade[:sec_id]} " \
                "#{trade[:action]} #{trade[:size]}"
    pos.pos_id
  end
  
  def position_qualified?(trade)
    true
  end
  
  def watch_for_config_requests(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:config][:m]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    set_hdr "(#{exchange.name}/#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      push_config
    end
  end

  def watch_for_trades(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:trade] + ".#{account_name}"
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      account_nm = headers.routing_key[/trades\.(.*)/, 1].to_sym
      trade = EntryStruct.from_hash(JSON.parse(payload))

      lstdout "->(#{headers.routing_key}) #{trade[:action]} #{trade[:size]} #{trade[:ticker]} @#{trade[:limit_price]}"
      logger.info "->(#{headers.routing_key}) #{trade[:action]} #{trade[:size]} #{trade[:ticker]} @#{trade[:limit_price]}", account_name
      logger.debug "->(#{headers.routing_key}) #{trade}", account_name                 

      logger.debug "next unless #{trade[:size].to_i} >= #{account.min_shares}", account_name
      next unless trade[:size].to_i >= account.min_shares

      next unless (trade.size.to_i/account.lot_size*account.lot_size > 0) 

      trade.entry_status = (trade.entry_status || "") + "init;"
    
      if position_qualified?(trade) then
        trade.pos_id = new_position(trade)
    
        routing_key = ZtsApp::Config::ROUTE_KEY[:submit][:order]
        logger.info "<-#{exchange.name}/#{routing_key}: (#{trade.pos_id}) #{trade[:action]} "\
                    "#{trade[:size]} "  \
                    "#{trade[:ticker]} ->#{trade[:broker]}", account_name
        logger.debug "<-(#{exchange.name}/#{routing_key}: #{trade}", account_name
        lstdout "<- (#{routing_key}) #{trade.to_human}"
        exchange.publish(trade.attributes.to_json, :routing_key => routing_key, :persistent => true)
      else
        lstderr "watch_for_trades: position not qualified for trade #{trade}"
      end
    end
  end
    
  def run    
    EventMachine.run do
#      timer = EventMachine::PeriodicTimer.new(20) do
#        $stderr.puts "#{proc_name}: the time is #{Time.now}"
#      end
      
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
  
      channel = AMQP::Channel.new(connection)  
      @exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], 
                                ZtsApp::Config::EXCHANGE[:core][:options])
    
      logger.amqp_config(channel)
      watch_admin_messages(channel)
      config
      watch_for_config_requests(channel)
      watch_for_trades(channel)
      
      write_hdr
      #clear
    end
  end
end
