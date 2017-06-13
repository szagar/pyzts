#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"

require "rubygems"
require "ib-ruby"
require "s_m"
require "fill_struct"
require "zts_ib_constants"
require 'action_view'
require 'bunny'
require "mkt_subscriptions"
require "log_helper"
require 'my_config'

class EWrapper
  include LogHelper
  attr_accessor :tick_types, :logger
  attr_accessor :channel, :md_channel
  attr_reader :account_code, :this_account_code, :this_broker, :sec_master
  attr_reader :mkt_subs

  def initialize(ib,this_broker)
    @ib = ib
    @this_broker = this_broker
    @tick_types = Hash.new
    tick_types.default(0)
    
    Zts.configure do |config|
      config.setup
    end

    opts = {}
    broker_config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      this_broker})
    @mkt_data_server    = broker_config.md_status == "true" ? true : false

    progname = File.basename(__FILE__,".rb") 
    
    @sec_master = SM.instance
    @mkt_subs           = MktSubscriptions.instance

    amqp_factory = AmqpFactory.instance

    if @mkt_data_server
      show_info "md_connection = Bunny.new( #{amqp_factory.md_params} )"
      md_connection = Bunny.new( amqp_factory.md_params )
      md_connection.start
    end

    show_info "connection = Bunny.new( #{amqp_factory.params} )"
    connection = Bunny.new( amqp_factory.params )
    connection.start

    @channel  = connection.create_channel
    if @mkt_data_server
      @md_channel  = md_connection.create_channel
      @md_exchange = md_channel.topic(Zts.conf.amqp_exch_mktdata,
                                      Zts.conf.amqp_exch_options)
    end
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
    market,id = sec_master.decode_ticker(ticker_id)    # IB::SECURITY_TYPES
    "#{std_route}.#{market}.#{id}"
  end
    
  def info_subscriptions
    @ib.subscribe(:Alert) { |msg| 
      show_info "#{msg.to_human}" 
      #debug "#{msg.inspect}"

      payload = msg.to_human 
      routing_key = Zts.conf.rt_alert
      exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                               Zts.conf.amqp_exch_mktdata_options)
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
        @account_code = msg.data[:value]
#puts "CHECKOUT: if ( #{account_code} != #{this_account_code} ) then"
#        if ( account_code != this_account_code ) then
#          alert "wrong account code #{msg.data[:value]} (#{this_account_code})"
#        end
      end
      #ts = Time.parse msg.created_at
      #debug "payload(#{cnt}) = {account: #{msg.data[:account_name]}, key: #{msg.data[:key]}, value: #{msg.data[:value]}}.to_json"
      key = msg.data[:key].tr("-","_")
      payload = {cnt: cnt, account: msg.data[:account_name], key: key, value: msg.data[:value], ts: msg.created_at}.to_json
      routing_key = Zts.conf.rt_acct_balance
      exchange = channel.topic(Zts.conf.amqp_exch_db,
                               Zts.conf.amqp_exch_options)
      show_info "<-(#{exchange.name}/#{routing_key}): AccountValue: #{msg.data[:account_name]} #{key} => #{msg.data[:value]}"
      exchange.publish(payload, :routing_key => routing_key)
    }
    

    @ib.subscribe(:PortfolioValue) { |msg| 
      debug msg.to_human
      debug msg.inspect
      data = msg.data 
      contract = data[:contract]
=begin
RESEARCH: {:version=>7, :contract=>{:con_id=>80986742, :symbol=>"GM", :sec_type=>"STK", :expiry=>"", :strike=>0.0, :right=>"0", :multiplier=>"", :primary_exchange=>"NYSE", :currency=>"USD", :local_symbol=>"GM"}, :position=>103, :market_price=>39.0699997, :market_value=>4024.21, :average_cost=>39.16970875, :unrealized_pnl=>-10.27, :realized_pnl=>0.0, :account_name=>"DU139750"}
=end
      show_info "PFv: #{data[:account_name]} #{contract[:symbol]}(#{contract[:primary_exchange]}) "\
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
      show_info "->#{exchange.name}.publish(#{payload}, :routing_key => #{routing_key})"
      exchange.publish(payload, :routing_key => routing_key)
    }
    
    @ib.subscribe(:CommissionReport) { |msg|       
      show_info msg.to_human 
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
      show_info "IB->ExecutionData"
      debug "NA#{msg.to_human}"
      debug "#{msg.inspect}"

      exec = msg.data[:execution]
      con  = msg.data[:contract]
      debug "ExecutionData.execution: #{exec.inspect}"
      debug "ExecutionData.contract: #{con.inspect}"
      pos_id = exec[:order_ref] || -1

      show_info "ExecutionData tkr:#{con[:symbol]} pos_id:#{exec[:order_ref]} exch:#{exec[:exchange]} side:#{exec[:side]} qyt:#{exec[:quantity]} px:#{exec[:price]} cumqty:#{exec[:cumulative_quantity]} avgpx:#{exec[:average_price]}"

      params = exec.merge(con)
      params = exec.merge({pos_id: exec[:order_ref], avg_price: exec[:average_price], action: ZTS::IB.action(exec[:side]), broker: this_broker})
      fill = FillStruct.from_hash( params )

      show_info "Fill: #{fill}"
      routing_key = Zts.conf.rt_fills
      exchange = channel.topic(Zts.conf.amqp_exch_flow,
                               Zts.conf.amqp_exch_options)
      show_info "<-(#{exchange.name}/#{routing_key}/#{pos_id}): (#{fill.attributes})"
      exchange.publish(fill.attributes.to_json, :routing_key => routing_key, :message_id => pos_id, :persistent => true)
    end
    
    # order data
    
    @ib.subscribe(:OrderStatus) { |msg| 
      debug msg.to_human 
      debug "Checkout:#{msg.inspect}"
      
      data=msg.data
      order    = data[:order]
      contract = data[:contract]
      state    = data[:order_state]
      state[:broker_ref] = state[:local_id]

      debug "Checkout:order    = #{order}"
      debug "Checkout:contract = #{contract}"
      debug "Checkout:state    = #{state}"
      routing_key = Zts.conf.rt_order_status
      exchange    = channel.topic(Zts.conf.amqp_exch_db,
                                  Zts.conf.amqp_exch_options)
      debug "<-(#{exchange.name}/#{routing_key}): #{state}.to_json"
      exchange.publish(state.to_json, :routing_key => routing_key, :persistent => true)
    }
    
    @ib.subscribe(:OpenOrder) { |msg| 
      msg.order.save
      debug msg.to_human 
      debug "#{msg.inspect}"
      
      data=msg.data
      ord = data[:order]
      con = data[:contract]
      state = data[:order_state]
      show_info "OpenOrder: #{con[:symbol]} pos_id:#{ord[:order_ref]} status:#{state[:status]} #{ord[:action]} #{ord[:total_quantity]}/#{state[:filled]} @#{ord[:limit_price]} opncls:#{ord[:open_close]} client_id:#{ord[:client_id]}"
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
                          broker:         this_broker,
      )

      routing_key = Zts.conf.rt_open_order
      exchange = channel.topic(Zts.conf.amqp_exch_db,
                               Zts.conf.amqp_exch_options)
      show_info "<-(#{exchange.name}/#{routing_key}): order.to_json"
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
    
    @ib.subscribe(:AccountDownloadEnd) do |msg| 
      show_info "#{account_code}: AccountDownloadEnd msg=#{msg}"
    end
    
    md_subscriptions if @mkt_data_server

#    Signal.trap("INT") { puts "interrupted caught in EWrapper"; exit }
    
  end

  def md_subscriptions
    @ib.subscribe(:RealTimeBar) { |msg|
      tick_types[msg.data[:tick_type]] =+ 1
      routing_key = md_routing_key(Zts.conf.rt_bar5s, msg.data[:request_id])
      show_info msg.data
      print "."
      market,sec_id = sec_master.decode_ticker(msg.data[:request_id])
      payload = msg.data[:bar].merge(mkt: market, sec_id: sec_id)
      show_info "#{@md_exchange.name}.publish(#{payload}.to_json, :routing_key => #{routing_key})"
      @md_exchange.publish(payload.to_json, :routing_key => routing_key)
      mkt_subs.refresh(sec_id) #if md_monitor?
    }

    # market data subscriptions
    @ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) do |msg|
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.to_human
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      msg.data[:tick_type_str] = IB::TICK_TYPES[msg.data[:tick_type]]
      payload = msg.data.to_json
      tick_types[msg.data[:tick_type]] =+ 1
      routing_key = md_routing_key('tick', msg.data[:ticker_id])
      exchange = md_channel.topic(Zts.conf.amqp_exch_core,
                               Zts.conf.amqp_exch_options)
      print "-"
      exchange.publish(payload, :routing_key => routing_key)
    end

  end
  
end

