#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
#$: << "#{ENV['ZTS_HOME']}/lib"

require "rubygems"
require "ib-ruby"
require "s_m"
require "fill"
require "zts_ib_constants"
require 'action_view'

class EWrapper
  attr_reader :channel_ib_account_balance
  attr_reader :channel_ib_portfolio_value
  attr_reader :channel_ib_commission_data
  attr_reader :channel_ib_execution
  attr_reader :channel_ib_order_status
  attr_reader :channel_ib_open_order 
  attr_reader :channel_ib_bar5s 
  attr_reader :redis

  def initialize(ib)
    @ib = ib
    
    redis_channels = Configuration.new({filename: 'redis_channels.yml',
                                        env:      'development'})

    @channel_ib_account_balance = redis_channels.account_balance
    @channel_ib_portfolio_value = redis_channels.portfolio_value
    @channel_ib_commission_data = redis_channels.commission_data
    @channel_ib_execution       = redis_channels.execution
    @channel_ib_order_status    = redis_channels.order_status
    @channel_ib_open_order      = redis_channels.open_order 
    @channel_ib_bar5s           = redis_channels.bar5s 

    progname = File.basename(__FILE__,".rb") 

    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end
  
  def info str
    puts str
  end
  def debug str
    puts str
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
      info msg.to_human 
    }

    cnt = 0
    @ib.subscribe(:AccountValue, :AccountUpdateTime) { |msg| 
      puts "msg"
      cnt += 1
      debug msg.to_human 
      debug "#{msg.inspect}"
      next unless msg.data[:version] == 2
      key = msg.data[:key].tr("-","_")
      payload = {
        cnt:     cnt,
        account: msg.data[:account_name],
        key:     key,
        value:   msg.data[:value]
      }

      redis.publish channel_ib_account_balance, payload.to_json
    }
    

    @ib.subscribe(:PortfolioValue) do |msg| 
      puts "msg"
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
      }
      redis.publish channel_ib_portfolio_value, payload.to_json
    end
    
    @ib.subscribe(:CommissionReport) do |msg|       
      info msg.to_human 
      debug "#{msg.inspect}"
      puts "redis.publish #{channel_ib_commission_data}, msg.data.to_json"
      redis.publish channel_ib_commission_data, msg.data.to_json
    end
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

      fill = Fill.new(ref_id: '11111', pos_id: pos_id,
                      sec_id: SM.sec_lookup(con[:symbol]),
                      exec_id: exec[:exec_id],
                      price: exec[:price], avg_price: exec[:average_price],
                      qty: exec[:quantity], action: action,
                      broker: m.this_broker, account: exec[:account_name])

      info "Fill: #{fill}"
      redis.publish channel_ib_execution, msg.data.to_json
    end
    
    # market data subscriptions
    @ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) do |msg|
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.to_human
      debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      msg.data[:tick_type_str] = IB::TICK_TYPES[msg.data[:tick_type]]
      payload = msg.data.to_json
      print "-"
    end
    
    # order data
    @ib.subscribe(:OrderStatus) do |msg| 
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
      
      order_update = {
        perm_id:    state[:perm_id],
        status:     state[:status],
        filled_qty: state[:filled], 
        leaves:     state[:remaining],
        avg_price:  state[:average_fill_price], 
        parent_id:  state[:parent_id]
      }
      redis.publish channel_ib_order_status, order_update.to_json
    end
    
    @ib.subscribe(:OpenOrder) do |msg| 
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
      
      order = OrderStruct.from_hash(  account:     ord[:account], 
                                      perm_id:     ord[:perm_id],
                                      pos_id:      ord[:order_ref],
                                      ticker:      con[:symbol], 
                                      status:      state[:status],
                                      action:      ord[:action],
                                      order_qty:   ord[:total_quantity],
                                      leaves:      state[:remaining],
                                      filled_qty:  state[:filled],
                                      avg_price:   state[:average_fill_price], 
                                      price_type:  ord[:order_type],
                                      tif:         ord[:tif],
                                      limit_price: ord[:limit_price], 
                                      broker:      m.this_broker,
                                      broker_ref:  ord[:local_id],
                                      notes:       state[:warning_text]
                                   )
      redis.publish channel_ib_open_order, order.to_json
    end
    
    @ib.subscribe(:TickOptionComputation) { |msg| 
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect 
    }
    
    @ib.subscribe(:TickEFP) { |msg| 
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
    }
    
    @ib.subscribe(:RealTimeBar) do |msg| 
      channel = md_routing_key(channel_ib_bar5s, msg.data[:request_id])
      
      print "."
      redis.publish channel, msg.data[:bar].to_json
    end
    
    @ib.subscribe(:AccountDownloadEnd) do |msg| 
      info "#{m.account_code}: AccountDownloadEnd msg=#{msg}"
    end
  end
end

