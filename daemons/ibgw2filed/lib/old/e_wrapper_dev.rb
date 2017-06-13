#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
#$: << "#{ENV['ZTS_HOME']}/lib"

require "rubygems"
require "ib-ruby"
require "zts_ib_constants"
#require 'zts_config'
require 'bunny'

class EWrapperDev
  attr_accessor :m, :tick_types, :logger
  attr_accessor :channel

  def initialize(ib,m)
    @ib = ib
    @m = m
    
    
    puts "connection = Bunny.new( host: #{ZtsApp::Config::AMQP[:host]})"
    connection = Bunny.new( host: ZtsApp::Config::AMQP[:host])
    connection.start

    @channel  = connection.create_channel
  end
  
  def run
    info_subscriptions
    std_subscriptions
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
      routing_key = ZtsApp::Config::ROUTE_KEY[:data][:alert]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name], 
                               ZtsApp::Config::EXCHANGE[:market][:options])
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
        if ( m.account_code != ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code] ) then
          m.alert "wrong account code #{msg.data[:value]} (#{ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code]})"
        end
      end
      #debug "payload(#{cnt}) = {account: #{msg.data[:account_name]}, key: #{msg.data[:key]}, value: #{msg.data[:value]}}.to_json"
      key = msg.data[:key].tr("-","_")
      payload = {cnt: cnt, account: msg.data[:account_name], key: key, value: msg.data[:value]}.to_json
      routing_key = ZtsApp::Config::ROUTE_KEY[:data][:account][:balance]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:db][:name], 
                               ZtsApp::Config::EXCHANGE[:core][:options])
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

      routing_key = ZtsApp::Config::ROUTE_KEY[:data][:account][:position]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:db][:name],
                               ZtsApp::Config::EXCHANGE[:core][:options])
      info "->#{exchange.name}.publish(#{payload}, :routing_key => #{routing_key})"
      exchange.publish(payload, :routing_key => routing_key)
    }
    
    @ib.subscribe(:CommissionReport) { |msg|       
      info msg.to_human 
      debug "#{msg.inspect}"

      data = msg.data
      #info "DBG:CmmRpt exec_id:#{data[:exec_id]} comm:#{data[:commission]} real:#{data[:realized_pnl]} yield:#{data[:yield]}"

      payload = data 
      routing_key = ZtsApp::Config::ROUTE_KEY[:data][:commission]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                               ZtsApp::Config::EXCHANGE[:market][:options])
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
      debug "FILL: Fill.new(pos_id: #{pos_id}, sec_id: #{SM.sec_lookup(con[:symbol])},"\
                "price: #{exec[:price]},  avg_price: #{exec[:average_price]}," \
                "qty: #{exec[:quantity]}, action: #{action}," \
                "broker: #{m.this_broker}, account: #{exec[:account_name]})"
                #, action2: order.action2, broker: broker)

      fill = Fill.new(ref_id: '11111', pos_id: pos_id, sec_id: SM.sec_lookup(con[:symbol]),
                      exec_id: exec[:exec_id],
                      price: exec[:price], avg_price: exec[:average_price],
                      qty: exec[:quantity], action: action,
                      broker: m.this_broker, account: exec[:account_name])
                      #, action2: order.action2, broker: broker)    

      info "Fill: #{fill}"
      routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:fills]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:order_flow][:name],
                               ZtsApp::Config::EXCHANGE[:core][:options])
      info "<-(#{exchange.name}/#{routing_key}/#{pos_id}): Marshal.dump(fill)"
      debug "<-(#{exchange.name}/#{routing_key}/#{pos_id}): Marshal.dump(#{fill})"
      exchange.publish(Marshal.dump(fill), :routing_key => routing_key, :message_id => pos_id, :persistent => true)
    end
    
    # market data subscriptions
    @ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) do |msg|
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.to_human
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      msg.data[:tick_type_str] = IB::TICK_TYPES[msg.data[:tick_type]]
      payload = msg.data.to_json
      tick_types[msg.data[:tick_type]] =+ 1
      routing_key = md_routing_key('tick', msg.data[:ticker_id])
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                               ZtsApp::Config::EXCHANGE[:core][:options])
      print "-"
      exchange.publish(payload, :routing_key => routing_key)
    end
    
    # order data
    #ZtsLogger#data: TWS Error 202: Order Canceled - reason:
    #msg=#<IB::Messages::Incoming::OrderStatus:0x007fdac5f933f8 @created_at=2013-03-19 20:10:20 -0400, @socket=#<IB::IBSocket:fd 7>, @data={:version=>6, :order_state=>{:local_id=>6, :status=>"Cancelled", :filled=>0, :remaining=>435, :average_fill_price=>0.0, :perm_id=>684164568, :parent_id=>0, :last_fill_price=>0.0, :client_id=>434098368, :why_held=>""}}, @order_state=<OrderState: Cancelled #6/684164568 from 434098368 filled 0/435 at 0.0/0.0 why_held >>
    #ord=
    #con=
    #state={:local_id=>6, :status=>"Cancelled", :filled=>0, :remaining=>435, :average_fill_price=>0.0, :perm_id=>684164568, :parent_id=>0, :last_fill_price=>0.0, :client_id=>434098368, :why_held=>""}
    #ZtsLogger#data: <-(order_flow/flow.order.state): order_update.to_json
    
    @ib.subscribe(:OrderStatus) { |msg| 
      puts msg.to_human 
      puts "#{msg.inspect}"
      
      order_state = msg.order_state
      
      data=msg.data
      
      puts "msg=#{msg.inspect}"
      ord = data[:order]
      puts "ord=#{ord}"
      con = data[:contract]
      puts "con=#{con}"
      state = data[:order_state]
      puts "state=#{state}"
      #debug "DBG:OrdSt #{state[:local_id]} #{state[:status]} #{state[:filled]}R#{state[:remaining]} @#{state[:average_price]}/#{state[:last_fill_price]} perm_id:#{state[:perm_id]} parent_id:#{state[:parent_id]} client_id:#{state[:client_id]}"
      
      order_update = {  perm_id: state[:perm_id], status: state[:status], filled_qty: state[:filled], 
                        leaves: state[:remaining], avg_price: state[:average_fill_price], 
                        parent_id: state[:parent_id] }
      
      routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:order_state]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:db][:name],
                               ZtsApp::Config::EXCHANGE[:core][:options])
      info "<-(#{exchange.name}/#{routing_key}): order_update.to_json"
      debug "<-(#{exchange.name}/#{routing_key}): #{order_update.inspect}.to_json"
      exchange.publish(order_update.to_json, :routing_key => routing_key, :persistent => true)
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
      
      order = OrderStruct.from_hash(  account:    ord[:account], 
                          perm_id:    ord[:perm_id],      pos_id:     ord[:order_ref],ticker:     con[:symbol], 
                          status:     state[:status],     action:     ord[:action],   order_qty:  ord[:total_quantity],
                          leaves:     state[:remaining],  filled_qty: state[:filled], avg_price:  state[:average_fill_price], 
                          price_type: ord[:order_type],   tif:        ord[:tif],      limit_price:ord[:limit_price], 
                          broker:     m.this_broker,      broker_ref: ord[:local_id], notes:      state[:warning_text])

      routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:ib][:open_order]
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:db][:name],
                               ZtsApp::Config::EXCHANGE[:core][:options])
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
      routing_key = md_routing_key(ZtsApp::Config::ROUTE_KEY[:data][:bar5s], msg.data[:request_id])
      exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                               ZtsApp::Config::EXCHANGE[:market][:options])
      
      print "."
      #info "bar data : ==#{msg.data[:bar].inspect}=="
      exchange.publish(msg.data[:bar].merge(sec_id: msg.data[:request_id]).to_json, :routing_key => routing_key)

    }
    
    @ib.subscribe(:AccountDownloadEnd) do |msg| 
      info "#{m.account_code}: AccountDownloadEnd msg=#{msg}"
    end
    
#    Signal.trap("INT") { puts "interrupted caught in EWrapper"; exit }
    
  end
  
end

