#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
#$: << "#{ENV['ZTS_HOME']}/lib"

require "rubygems"
require "ib-ruby"
require "s_m"
require "fill_struct"
require "zts_ib_constants"
require 'action_view'
#require 'zts_config'
require 'bunny'
require 'simple_logger'
require 'my_config'
require 'log_helper'

class EWrapper
  include SimpleLogger
  include LogHelper
  attr_accessor :m, :tick_types, :logger
  attr_accessor :channel

  def initialize(ib,m)
    @ib = ib
    @m = m
    @tick_types = Hash.new
    tick_types.default(0)
    
    Zts.configure do |config|
      config.setup
    end

    progname = File.basename(__FILE__,".rb") 
    simpleLoggerSetup(progname)
    
    amqp_factory = AmqpFactory.instance
    info "connection = Bunny.new( #{amqp_factory.params} )"
    connection = Bunny.new( amqp_factory.params )
    connection.start

    @channel  = connection.create_channel
  end
  
  def run
    info_subscriptions
    std_subscriptions
  end

  def report
    tick_types.each do |k,v|
      puts "#{k} :  #{v}"
    end
  end
  
  def md_routing_key(std_route,ticker_id)
    market,id = SM.decode_ticker(ticker_id)    # IB::SECURITY_TYPES
    "#{std_route}.#{market}.#{id}"
  end
    
  def info_subscriptions
    @ib.subscribe(:Alert) { |msg| 
      info "#{msg.to_human}" 
      #debug "#{msg.inspect}"

      payload = msg.to_human 
      routing_key = Zts.conf.rt_alert
      exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                               Zts.conf.amqp_exch_options)
      puts "========>>>>>>>#{exchange.name}.publish(#{payload}, :routing_key => #{routing_key})"
      exchange.publish(payload, :routing_key => routing_key)
    }

    cnt = 0
    @ib.subscribe(:AccountValue, :AccountUpdateTime) { |msg| 
      cnt += 1
      debug msg.to_human 
      debug "#{msg.inspect}"
      next unless msg.data[:version] == 2
      if (msg.data[:key].eql? 'AccountCode')
        m.account_code = msg.data[:value]
puts "CHECKOUT: if ( #{m.account_code} != #{ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code]} ) then"
        if ( m.account_code != ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code] ) then
          m.alert "wrong account code #{msg.data[:value]} (#{ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code]})"
        end
      end
      #debug "payload(#{cnt}) = {account: #{msg.data[:account_name]}, key: #{msg.data[:key]}, value: #{msg.data[:value]}}.to_json"
      key = msg.data[:key].tr("-","_")
      payload = {cnt: cnt, account: msg.data[:account_name], key: key, value: msg.data[:value]}.to_json
      routing_key = Zts.conf.rt_acct_balance
      exchange = channel.topic(Zts.conf.amqp_exch_db,
                               Zts.conf.amqp_exch_options)
      info "<-(#{exchange.name}/#{routing_key}): AccountValue: #{msg.data[:account_name]} #{key} => #{msg.data[:value]}"
      exchange.publish(payload, :routing_key => routing_key)
    }
    

    @ib.subscribe(:PortfolioValue) { |msg| 
      debug msg.to_human
      debug msg.inspect
      data = msg.data 
      contract = data[:contract]
      info "PFv: #{data[:account_name]} #{contract[:symbol]}(#{contract[:primary_exchange]}) "\
                    "#{ActionView::Base.new.number_with_delimiter(data[:position])} "\
                    "@#{data[:market_price]} $#{data[:market_value]} "\
                    "cost:#{ActionView::Base.new.number_to_currency(data[:average_cost])} " \
                    "PnL:#{data[:realized_pnl]}/#{data[:unrealized_pnl]}"

      payload = {
        :ticker => contract[:symbol],
        #:sec_id => SM.sec_lookup(contract[:symbol]),
        :position => data[:position],
        :market_price => data[:market_price],
        :market_value => data[:market_value],
        :average_price => data[:average_cost],
        :unrealized_pnl => data[:unrealized_pnl],
        :realized_pnl => data[:realized_pnl],
        :broker_account => data[:account_name]
      }.to_json

      routing_key = Zts.conf.rt_acct_position
      exchange = channel.topic(Zts.conf.amqp_exch_db,
                               Zts.conf.amqp_exch_options)
      info "->#{exchange.name}.publish(#{payload}, :routing_key => #{routing_key})"
      exchange.publish(payload, :routing_key => routing_key)
    }
    
    @ib.subscribe(:CommissionReport) { |msg|       
      info msg.to_human 
      debug "#{msg.inspect}"

      data = msg.data

      payload = data 
      routing_key = Zts.conf.rt_comm
      exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                               Zts.conf.amqp_exch_options)
      exchange.publish(payload.to_json, :routing_key => routing_key, :persistent => true)
    }
  end
  
  def std_subscriptions
    # Interactive Brokers subscriptions

    # execution data
    @ib.subscribe(:ExecutionData) do |msg| 
      info "IB->ExecutionData"
      debug "NA#{msg.to_human}"
      debug "#{msg.inspect}"

      exec = msg.data[:execution]
      con  = msg.data[:contract]
      debug "ExecutionData.execution: #{exec.inspect}"
      debug "ExecutionData.contract: #{con.inspect}"
      pos_id = exec[:order_ref] || -1

      info "ExecutionData tkr:#{con[:symbol]} pos_id:#{exec[:order_ref]} exch:#{exec[:exchange]} side:#{exec[:side]} qyt:#{exec[:quantity]} px:#{exec[:price]} cumqty:#{exec[:cumulative_quantity]} avgpx:#{exec[:average_price]}"

      action = ZTS::IB.action(exec[:side])

      params = exec.merge({pos_id: exec[:order_ref], avg_price: exec[:average_price], action: action})
      fill = FillStruct.from_hash( params )

      info "Fill: #{fill}"
      routing_key = Zts.conf.rt_fills
      exchange = channel.topic(Zts.conf.amqp_exch_flow,
                               Zts.conf.amqp_exch_options)
      info "<-(#{exchange.name}/#{routing_key}/#{pos_id}): (fill.attributes)"
      debug "<-(#{exchange.name}/#{routing_key}/#{pos_id}): (#{fill.attributes})"
      exchange.publish(fill.attributes.to_json, :routing_key => routing_key, :message_id => pos_id, :persistent => true)
    end
    
    # market data subscriptions
    @ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) do |msg|
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.to_human
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      msg.data[:tick_type_str] = IB::TICK_TYPES[msg.data[:tick_type]]
      payload = msg.data.to_json
      tick_types[msg.data[:tick_type]] =+ 1
      routing_key = md_routing_key('tick', msg.data[:ticker_id])
      exchange = channel.topic(Zts.conf.amqp_exch_core,
                               Zts.conf.amqp_exch_options)
      print "-"
      exchange.publish(payload, :routing_key => routing_key)
    end
    
    # order data
    
    @ib.subscribe(:OrderStatus) { |msg| 
      puts msg.to_human 
      puts "Checkout:#{msg.inspect}"
      
      data=msg.data
      order    = data[:order]
      contract = data[:contract]
      state    = data[:order_state]
      state[:broker_ref] = state[:local_id]

      puts "Checkout:order    = #{order}"
      puts "Checkout:contract = #{contract}"
      puts "Checkout:state    = #{state}"
      routing_key = Zts.conf.rt_order_status
      exchange    = channel.topic(Zts.conf.amqp_exch_db,
                                  Zts.conf.amqp_exch_options)
      debug "<-(#{exchange.name}/#{routing_key}): #{state}.to_json"
      exchange.publish(state.to_json, :routing_key => routing_key, :persistent => true)
      
=begin
      order_update = { :order=>{
                                   :local_id       =>  order[:local_id],
                                   :action         =>  order[:action],
                                   :total_quantity =>  order[:total_quantity],
                                   :order_type     =>  order[:order_type],
                                   :limit_price    =>  order[:limit_price],
                                   :tif            =>  order[:tif],
                                   :account        =>  order[:account],
                                   :open_close     =>  order[:open_close],
                                   :order_ref      =>  order[:order_ref],
                                    :client_id     =>  order[:client_id],
                                    :perm_id       =>  order[:perm_id],
                                    :parent_id     =>  order[:parent_id]            },
                    :contract=>{
                                    :con_id        =>  contract[:con_id],
                                    :symbol        =>  contract[:symbol],
                                    :sec_type      =>  contract[:sec_type],
                                    :expiry        =>  contract[:expiry],
                                    :strike        =>  contract[:strike],
                                    :exchange      =>  contract[:exchange]    },
                    :order_state=>{
                                    :status        =>  state[:status],
                                    :commission    =>  state[:commission],
                                    :warning_text  =>  state[:warning_text],   }
                 }


#      order_update = {  order_ref: order[:order_ref], perm_id: state[:perm_id], status: state[:status],
#                        filled_qty: state[:filled], 
#                        leaves: state[:remaining], avg_price: state[:average_fill_price], 
#                        parent_id: state[:parent_id] }
      
      #routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:order_state]
      routing_key = Zts.conf.rt_order_status
      #exchange = channel.topic(ZtsApp::Config::EXCHANGE[:db][:name],
      #                         ZtsApp::Config::EXCHANGE[:core][:options])
      exchange = channel.topic(Zts.conf.amqp_exch_db,
                               Zts.conf.amqp_exch_options)
      info "<-(#{exchange.name}/#{routing_key}): order_update.to_json"
      debug "<-(#{exchange.name}/#{routing_key}): #{order_update.inspect}.to_json"
      exchange.publish(order_update.to_json, :routing_key => routing_key, :persistent => true)
=end
    }
    
    @ib.subscribe(:OpenOrder) { |msg| 
      msg.order.save
      debug msg.to_human 
      debug "#{msg.inspect}"
      
      data=msg.data
      ord = data[:order]
      con = data[:contract]
      state = data[:order_state]
      info "OpenOrder: #{con[:symbol]} pos_id:#{ord[:order_ref]} status:#{state[:status]} #{ord[:action]} #{ord[:total_quantity]}/#{state[:filled]} @#{ord[:limit_price]} opncls:#{ord[:open_close]} client_id:#{ord[:client_id]}"
      debug "OpenOrder.order: #{ord.inspect}"
      debug "OpenOrder.contract: #{con.inspect}"
      debug "OpenOrder.order_state: #{state.inspect}"
      
      order = OrderStruct.from_hash( 
                         #order_id:       ,
                         #setup_id:       ,
                         #entry_id:       ,
                         #sec_id:       ,
                          perm_id:        ord[:perm_id],
                          pos_id:         ord[:order_ref],
                          broker_ref:     ord[:local_id],

                          action:         ord[:action],
                          #action2:        ,
                          #mkt:            , 
                          #setup_src:      ,
                          #trade_type:     ,
                          #side:           ,
                          ticker:         con[:symbol], 
                          order_qty:      ord[:total_quantity],
                          tif:            ord[:tif],
                          leaves:         state[:remaining],
                          filled_qty:     state[:filled],
                          avg_price:      state[:average_fill_price], 
                          status:         state[:status],     
                          price_type:     ord[:order_type],
                          limit_price:    ord[:limit_price], 
                          stop_price:     ord[:limit_price], 
                          notes:          state[:warning_text],

                          #account_name:   ,
                          broker_account: ord[:account],
                          broker:         m.this_broker,
      )

      #routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:ib][:open_order]
      routing_key = Zts.conf.rt_open_order
      #exchange = channel.topic(ZtsApp::Config::EXCHANGE[:db][:name],
      #                         ZtsApp::Config::EXCHANGE[:core][:options])
      exchange = channel.topic(Zts.conf.amqp_exch_db,
                               Zts.conf.amqp_exch_options)
      info "<-(#{exchange.name}/#{routing_key}): order.to_json"
      debug "<-(#{exchange.name}/#{routing_key}): #{order}"
      exchange.publish(order.attributes.to_json, :routing_key => routing_key, :persistent => true)
    }
    
    @ib.subscribe(:TickOptionComputation) { |msg| 
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect 
      tick_types[msg.data[:tick_type]] =+ 1
    }
    
    @ib.subscribe(:TickEFP)               { |msg| 
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      tick_types[msg.data[:tick_type]] =+ 1
    }
    
    @ib.subscribe(:RealTimeBar) { |msg| 
      tick_types[msg.data[:tick_type]] =+ 1
      #routing_key = md_routing_key(ZtsApp::Config::ROUTE_KEY[:data][:bar5s], msg.data[:request_id])
      routing_key = md_routing_key(Zts.conf.rt_bar5s, msg.data[:request_id])
      #exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
      #                         ZtsApp::Config::EXCHANGE[:market][:options])
      exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                               Zts.conf.amqp_exch_options)
      
      print "."
      market,sec_id = SM.decode_ticker(msg.data[:request_id])
      payload = msg.data[:bar].merge(sec_id: sec_id)
      puts "#{exchange.name}.publish(#{payload}.to_json, :routing_key => #{routing_key})"
      exchange.publish(payload.to_json, :routing_key => routing_key)

    }
    
    @ib.subscribe(:AccountDownloadEnd) do |msg| 
      info "#{m.account_code}: AccountDownloadEnd msg=#{msg}"
    end
    
#    Signal.trap("INT") { puts "interrupted caught in EWrapper"; exit }
    
  end
  
end

