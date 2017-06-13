#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/etc"

require 'screen'
require 'json'
require 'amqp'
require 's_m'
require 'zts_config'
require 'adminable'
require 'zts_logger'
require 'entry_struct'
require 'account_proxy'
require 'log_helper'

class MoneyMgrBase
  include Adminable
  include LogHelper

  attr_accessor :money_mgr, :exchange, :accounts, :account_objs, :setups, :proc_name
  attr_accessor :logger
  
  def initialize(money_mgr)
    @money_mgr = money_mgr
    @proc_name = "mm_#{money_mgr}"
    
    @logger = ZtsLogger.instance
    logger.set_proc_name(proc_name)
    
    @account_objs=Hash.new
    @accounts = Hash.new
    @accounts.default(0)
    @setups = Hash.new
    
    set_hdr "Money Manager: #{money_mgr}          proc_name: #{proc_name}"
  end
  
  def clear
    write_hdr
  end
  
  def alert(str)
    lstderr str
  end
  
  def publish_config(account, setup, entry)
    routing_key = ZtsApp::Config::ROUTE_KEY[:config][:entry] + ".#{entry}"
    logger.debug "<-#{exchange.name}.publish({account: #{account}, setup: #{setup}}.to_json, :routing_key => #{routing_key})"
    exchange.publish({account: account, setup_src: setup, entry: entry}.to_json, :routing_key => routing_key)
  end
  
  def push_config
    accounts do |k,acct_hash|
      setup, entry = k.split("::")
      acct_hash.keys do |acct_name|
        publish_config(acct_name, setup, entry)
      end
    end
  end
  
  def config(channel)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:config][:money_mgr]}.#{money_mgr}"
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true).bind(exchange, :routing_key => routing_key).subscribe do |headers, payload|
      rec = JSON.parse(payload)
      logger.debug "->(#{headers.routing_key}): #{rec['account']} #{rec['setup']}/#{rec['entry']}"
      account = rec['account']
      setup = rec['setup']
      entry = rec['entry']
      k = "#{setup}::#{entry}"
      
      if not (accounts.member?(k) && accounts[k].member?(account)) then
        account_objs[account] = AccountProxy.new(account) unless account_objs.member?(account)
        accounts[k] = Hash.new unless accounts.member?(k)
        accounts[k][account] = account_objs[account]

        publish_config(account, setup, entry)
      end
    end
  end
  
  def request_mm_config(channel)
    # request money_mr config
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:config][:mm]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], 
                             ZtsApp::Config::EXCHANGE[:core][:options])
    exchange.publish("", :routing_key => routing_key)  
  end
  
  
  def watch_for_config_requests(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:config][:entry]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    set_hdr "(#{exchange.name}/#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      push_config
    end
  end
  

  def watch_for_entries(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:signal][:entry] + ".#" + ".#"
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true).bind(exchange, :routing_key => routing_key).subscribe do |headers, payload|

      # tt_swing | tt_position | tt_trades
      setup_src = headers.routing_key[/signal\.entry\.(.*)\..*/, 1]
      entry_strategy = headers.routing_key[/signal\.entry\..*\.(.*)/, 1]

      next unless accounts.member?("#{setup_src}::#{entry_strategy}")

      entry = EntryStruct.from_hash(JSON.parse(payload))
      entry.entry_name = entry_strategy

      # remove
      #entry.price       ||= (entry.side.eql?('long') ? SM.high(sec_id)
      #                                               : SM.low(sec_id)).to_f
      entry.limit_price ||= (entry.side.eql?('long') ? SM.high(sec_id)
                                                     : SM.low(sec_id)).to_f
      publish_to_money_managers(entry)
    end
  end
  
  def calc_size(trade)
    track "MM#calc_size: risk_dollars=#{trade.risk_dollars}  init_risk=#{trade.init_risk}"
    (trade.risk_dollars / trade.init_risk).round(0)
  end

#  def init_risk_by_stop_price(trade)
#    price = case trade.side
#    when "long"
#      [(trade.bo_price).to_f, SM.last(trade.sec_id), (trade.setup_trigger).to_f].max
#    when "short"
#      price1 = (trade.bo_pricei.empty? ? "99999":trade.bo_price).to_f
#      price2 = (trade.setup_trigger.empty? ? "99999":trade.setup_trigger).to_f
#      price3 =  SM.last(trade.sec_id)
#      [price1, price2, price3].min
#    end
#    risk = (price.to_f - trade.setup_stop_price.to_f).abs.round(2)
#  end

  def init_risk(trade)
    lstdout "init_risk(#{trade})"
    track "MM#init_risk: side=#{trade.side}  weak=#{trade.weak_support}  mod=#{trade.moderate_support}"

    side_factor = (trade.side == "long") ? 1 : -1
    case trade.trade_type
    when "Swing"
      trade.mm_stop_loss = (trade.weak_support.to_f - side_factor * ((trade.limit_price.to_f < 10.0) ? 0.12 : 0.25)).round(2)
    when "Position"
      trade.mm_stop_loss = (trade.moderate_support.to_f - side_factor * ((trade.limit_price.to_f < 10.0) ? 0.12 : 0.25)).round(2)
    else
      alert "No init_risk calc for trade_type:#{trade.trade_type}, use ATR"
      (trade.atr.to_f * trade.atr_factor.to_f).round(4)
    end

    track "MM#init_risk: mm_stop_loss=#{trade.mm_stop_loss}"

    (trade.limit_price.to_f - trade.mm_stop_loss.to_f).abs.round(2)
  end  
  
  def publish_to_money_managers(trade)
    logger.debug "publish_to_money_managers(#{trade.inspect})"

    # trade.setup_src = tt_swing | tt_position
    trade.atr = SM.atr(trade.sec_id)
    
    limit_price = Float(trade.limit_price)

    k = "#{trade.setup_src}::#{trade.entry_name}"
    accounts[k].each do |acct_name,acct_obj|
      trade.account  = acct_name
      #trade.dollar_pos = acct_obj.dollar_pos
      trade.broker     = acct_obj.broker
      trade.atr_factor = acct_obj.atr_factor.to_f
  
      trade.init_risk = init_risk(trade)
      track "MM#publish_to_money_managers: acct:#{acct_name} tkr=#{trade.ticker}  init_risk=#{trade.init_risk}  limit_price=#{limit_price}"

      if (not (trade.init_risk.to_f > 0)) then
        alert "O risk factor, skip this trade:#{trade}"
        next
      end 
      unless ((trade.init_risk.to_f <= (limit_price*0.20))) then
        alert "risk factor(#{trade.init_risk}) > #{limit_price*0.20} (20%) for trade:#{trade}"
        next
      end 

      trade.equity_model = acct_obj.equity_model
     # trade.risk_dollars = self.send(trade.equity_model, acct_obj)

      track "MM#publish_to_money_managers: call AccountProxy.#{trade.equity_model}_risk_dollars"
      trade.risk_dollars = acct_obj.send("#{trade.equity_model}_risk_dollars")
      track "returned with risk_dollars = #{trade.risk_dollars}"
      trade.size = calc_size(trade)
 
      #next unless acct_obj.funds_available?(Float(trade.size) * Float(limit_price))
  
      track "MM#: send trade, size=#{trade.size} tkr=#{trade.ticker} @#{trade.limit_price}"

      routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:trade] + ".#{acct_name}"
      lstdout "<-(#{exchange.name}:#{routing_key}): #{trade[:action]} #{trade[:ticker]} "\
              "#{trade[:sec_id]} #{trade[:size]} "\
              "stop:#{trade[:stop_price]}, R=#{trade[:init_risk]} "
      logger.debug "<-(#{exchange.name}/#{routing_key}): #{trade.inspect}"
      exchange.publish(trade.attributes.to_json, :routing_key => routing_key,
                                                 :persistent => true)
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
      config(channel)
      request_mm_config(channel)
      watch_for_entries(channel)
      watch_for_config_requests(channel)
      
      clear
    end
  end
end
