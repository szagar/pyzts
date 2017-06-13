#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"

require "rubygems"
require "ib-ruby"
require "s_m"
require "fill_struct"
require "zts_ib_constants"
require 'action_view'
require "mkt_subscriptions"
require "log_helper"
require 'my_config'
require "date_time_helper"

class EWrapper
  include LogHelper
  attr_accessor :tick_types, :logger
  attr_accessor :channel, :md_channel
  attr_reader :account_code, :this_account_code, :this_broker, :sec_master
  attr_reader :mkt_subs

  def initialize(ib,gw,this_broker)
    @ib = ib
    @gw = gw
    @this_broker = this_broker
    @tick_types = Hash.new
    tick_types.default(0)
    
    @debug_level = 3
    @info_level  = 2
    @warn_level  = 0
    @current_log_level = @debug_level

    @my_order_status = {}

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

    today = DateTimeHelper::integer_date
    ib_data_dir = "/Users/szagar/zts/data/ibdata"
    (@fh_order_status = File.open("#{ib_data_dir}/#{today}_order_status.csv", 'a')).sync = true
    (@fh_fills        = File.open("#{ib_data_dir}/#{today}_fills.csv", 'w')).sync = true
    (@fh_alerts       = File.open("#{ib_data_dir}/#{today}_alerts.csv", 'w')).sync = true
    (@fh_open_orders  = File.open("#{ib_data_dir}/#{today}_open_orders.csv", 'w')).sync = true
    (@fh_account_data = File.open("#{ib_data_dir}/#{today}_account_data.csv", 'w')).sync = true
    (@fh_rt_bars      = File.open("#{ib_data_dir}/#{today}_rt_bars.csv", 'w')).sync = true
    (@fh_tick_data    = File.open("#{ib_data_dir}/#{today}_tick_data.csv", 'w')).sync = true
    (@fh_portf_data   = File.open("#{ib_data_dir}/#{today}_portf_data.csv", 'w')).sync = true
    (@fh_comm_rpt     = File.open("#{ib_data_dir}/#{today}_comm_rpt.csv", 'w')).sync = true
  end
  
  def run
    info_subscriptions
    std_subscriptions
  end

  def set_log_level(lvl)
    info "Log Level for ewrapper set to #{lvl}"
    @current_log_level = lvl
  end

  def report
    tick_types.each do |k,v|
      debug "#{k} :  #{v}"
    end
  end
  
  def bs_order(o)
    size = (o[:pos_risk].to_f / (o[:stop_px].to_f-o[:stop_ex].to_f)).to_i
    info "stage order to buy #{size} #{o[:tkr]} @#{o[:stop_px]}, risking #{o[:pos_risk]}"

    # #-- Parent Order --
    # buy_order = IB::Order.new :total_quantity => 100,
    # :limit_price => order_price,
    # :action => 'BUY',
    # :order_type => 'LMT',
    # :algo_strategy => '',
    # :account => account_code,
    # :transmit => false
    # ib.wait_for :NextValidId
    # 
    # #-- Child STOP --
    # stop_order = IB::Order.new :total_quantity => 100,
    # :limit_price => 0,
    # :aux_price => stop_price,
    # :action => 'SELL',
    # :order_type => 'STP',
    # :account => account_code,
    # :parent_id => buy_order.local_id,
    # :transmit => true
    #
    # #-- Profit LMT
    # profit_order = IB::Order.new :total_quantity => 100,
    # :limit_price => profit_price,
    # :action => 'SELL',
    # :order_type => 'LMT',
    # :account => account_code,
    # :parent_id => buy_order.local_id,
    # :transmit => true
  end

  def ss_order(o)
    debug "ss_order(#{o})"
  end

  def md_routing_key(std_route,ticker_id)
    market,id = sec_master.decode_ticker(ticker_id)    # IB::SECURITY_TYPES
    "#{std_route}.#{market}.#{id}"
  end
    
  def info_subscriptions
    info "info_subscriptions"
    @ib.subscribe(:Alert) { |msg| 
      info "Alert: #{msg.to_human}" 
      #debug "#{msg.inspect}"

      payload = msg.to_human 
      @fh_alerts.write "#{payload}\n"
    }

    cnt = 0
    @ib.subscribe(:AccountValue, :AccountUpdateTime) { |msg| 
      cnt += 1
      #debug msg.to_human 
      #debug "#{msg.inspect}"
      next unless msg.data[:version] == 2
      #if (msg.data[:key].eql? 'AccountCode')
      #  @account_code = msg.data[:value]
      #end
      #ts = Time.parse msg.created_at
      #debug "payload(#{cnt}) = {account: #{msg.data[:account_name]}, key: #{msg.data[:key]}, value: #{msg.data[:value]}}.to_json"
      key = msg.data[:key].tr("-","_")
      #payload = {cnt: cnt, account: msg.data[:account_name], key: key, value: msg.data[:value], ts: msg.created_at}
      #@fh_account_data.write "#{payload.keys}\n"
      #@fh_account_data.write "#{payload.values}\n"
      #@fh_account_data.write "#{payload.to_json}\n"
      @gw.account[key]  = msg.data[:value]
    }
    

    @ib.subscribe(:PortfolioValue) { |msg| 
      #debug msg.to_human
      #debug msg.inspect
      data = msg.data 
      contract = data[:contract]
      #info "PFv: #{data[:account_name]} #{contract[:symbol]}(#{contract[:primary_exchange]}) "\
      #              "#{ActionView::Base.new.number_with_delimiter(data[:position])} "\
      #              "@#{data[:market_price]} $#{data[:market_value]} "\
      #              "cost:#{ActionView::Base.new.number_to_currency(data[:average_cost])} " \
      #              "PnL:#{data[:realized_pnl]}/#{data[:unrealized_pnl]}"

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
      }   #.to_json
      @fh_portf_data.write "#{payload}\n"

      @gw.portf[contract[:symbol]] = {}
      @gw.portf[contract[:symbol]][:position]       = data[:position]
      @gw.portf[contract[:symbol]][:market_price]   = data[:market_price]
      @gw.portf[contract[:symbol]][:market_value]   = data[:market_value]
      @gw.portf[contract[:symbol]][:average_price]  = data[:average_cost]
      @gw.portf[contract[:symbol]][:unrealized_pnl] = data[:unrealized_pnl]
      @gw.portf[contract[:symbol]][:realized_pnl]   = data[:realized_pnl]
      @gw.portf[contract[:symbol]][:broker_account] = data[:broker_account]
    }
    
    @ib.subscribe(:CommissionReport) { |msg|       
      info msg.to_human 
      debug "#{msg.inspect}"

      @fh_comm_rpt.write "#{msg.data}\n"
    }
  end
  
  def std_subscriptions
    info "std_subscriptions"
    # Interactive Brokers subscriptions

    # execution data
    @ib.subscribe(:ExecutionData) do |msg| 
      debug "NA#{msg.to_human}"
      debug "#{msg.inspect}"

      exec = msg.data[:execution]
      con  = msg.data[:contract]
      debug "ExecutionData.execution: #{exec.inspect}"
      debug "ExecutionData.contract: #{con.inspect}"
      str = sprintf("%s %s %s %5d %6.3f",exec[:time],con[:symbol],exec[:side],exec[:quantity],exec[:price])
      info "FILL: #{str}"
      pos_id = exec[:order_ref] || -1

      info "ExecutionData tkr:#{con[:symbol]} pos_id:#{exec[:order_ref]} exch:#{exec[:exchange]} side:#{exec[:side]} qyt:#{exec[:quantity]} px:#{exec[:price]} cumqty:#{exec[:cumulative_quantity]} avgpx:#{exec[:average_price]}"

      params = exec.merge(con)
      params = exec.merge({pos_id: exec[:order_ref], avg_price: exec[:average_price], action: ZTS::IB.action(exec[:side]), broker: this_broker})
      fill = FillStruct.from_hash( params )

      info "Fill: #{fill}"
      @fh_fills.write "#{fill.attributes}\n"
    end
    
    # order data
    
    @ib.subscribe(:OrderStatus) { |msg| 
      debug msg.to_human 
      debug "Checkout:#{msg.inspect}"
      
      #data=msg.data
      #state    = data[:order_state]

      #debug "data    :: #{data}"
      #debug "state   :: #{state}"

      data=msg.data
      debug "\ndata=#{data}"
      ord = data[:order]
      debug "\nord=#{ord}"
      con = data[:contract]
      debug "\ncon=#{con}"
      state = data[:order_state]
      debug "\nstate=#{state}"

      oid = state[:local_id]
      @gw.orders[oid] || @gw.orders[oid] = {}
      @gw.orders[oid][:oid]       = oid
      @gw.orders[oid][:pid]       = state[:parent_id]
      @gw.orders[oid][:perm_id]   = state[:perm_id]
      @gw.orders[oid][:status]    =  state[:status]
      @gw.orders[oid][:filled]    = state[:filled]
      @gw.orders[oid][:remaining] = state[:remaining]
      @gw.orders[oid][:avg_px]    = state[:average_fill_price]
      @gw.orders[oid][:last_fill_px] = state[:last_fill_price]

      str = sprintf "%5d/%5d%12s%5d/%5d%6.2f%6.2f\n",state[:parent_id],state[:local_id],state[:status],state[:filled],state[:remaining],state[:average_fill_price],state[:last_fill_price]
      debug "------------"
      debug str
      debug "1. #{oid}: #{@gw.orders[oid]}"
      debug "------------"
      @fh_order_status.write str

      debug "OrderStatus: local_id:#{state[:local_id]} status:#{state[:status]} filled: #{state[:filled]} remaining: #{state[:remaining]} avg_price: #{state[:average_fill_price]} last_fill_px: #{state[:last_fill_price]} parent_id: #{state[:parent_id]}  client_id:#{state[:client_id]} perm_id: #{state[:perm_id]}"
    }
    
    @ib.subscribe(:OpenOrderEnd) { |msg|
      puts "OpenOrderEnd received: #{msg}"
    }

    @ib.subscribe(:OpenOrder) { |msg| 
      msg.order.save
      debug msg.to_human 
      debug "#{msg.inspect}"
      debug msg

      data=msg.data
      ord = data[:order]
      con = data[:contract]
      state = data[:order_state]

      symbol = con[:symbol]

      oid = ord[:local_id]
      debug "#{ord[:parent_id]}/#{ord[:local_id]} #{symbol}"
      @gw.orders[oid] || @gw.orders[oid] = {}
      if ord[:parent_id] == 0
        debug "*********************** create new lookup for #{symbol}"
        @gw.order_lookup[symbol] = {}
        @gw.order_lookup[symbol]['parent'] = oid
        @gw.orders[oid] || @gw.orders[oid] = {}
        @gw.orders[oid]['side'] = 'long' if ord[:action] == "BUY"
        @gw.orders[oid]['side'] = 'short' if ord[:action] == "SELL"
      else
        #pid = @gw.order_lookup[symbol]['parent']
        pid = ord[:parent_id]
        debug "@gw.orders[#{pid}]=#{@gw.orders[pid]}"
        debug "ord=#{ord}"
        info "*********************** create child order for #{symbol}"
        if @gw.long?(symbol)
          debug "*********************** we be long"
          debug "ord[:order_type]=#{ord[:order_type]}"
          debug "ord[:aux_price] = #{ord[:aux_price]}"
          #debug "@gw.orders[pid]['limit_px'] = #{ @gw.orders[pid][:limit_px]}"
          #if ord[:order_type] == "STP" && ord[:aux_price] < @gw.orders[pid][:limit_px]
          #  debug "*********************** stoploss order"
          #  @gw.order_lookup[symbol]['stoploss'] = oid
          #else
          #  debug "*********************** target order"
          #  @gw.order_lookup[symbol]['target'] = oid
          #end
        elsif @gw.short?(symbol)
          debug "*********************** we be short"
          debug "ord[:order_type]=#{ord[:order_type]}"
          debug "ord[:aux_price] = #{ord[:aux_price]}"
          #if ord[:limit_price] > @gw.orders[pid]['limit_px']
          #  debug "*********************** stoploss order"
          #  @gw.order_lookup[symbol]['stoploss'] = oid
          #else
          #  debug "*********************** target order"
          #  @gw.order_lookup[symbol]['target'] = oid
          #end
        else
          #debug "WARN: side must be either long or short, not #{@gw.order_lookup[symbol]['side']}"
          debug "WARN: side must be either long or short, "
        end
      end
      debug "@gw.orders[oid]=#{@gw.orders[oid]}"
      debug "@gw.orders[oid][:pid]=#{@gw.orders[oid][:pid]}"
      debug "ord[:parent_id]=#{ord[:parent_id]}"
      @gw.orders[oid][:pid]        = ord[:parent_id]
      @gw.orders[oid][:perm_id]    = ord[:perm_id]
      @gw.orders[oid][:symbol]     = symbol
      @gw.orders[oid][:sec_type]   = con[:sec_type]
      @gw.orders[oid][:status]     = state[:status]
      @gw.orders[oid][:commission] = state[:commission]
      @gw.orders[oid][:warning]    = state[:warning_text]
      @gw.orders[oid][:action]     = ord[:action]
      @gw.orders[oid][:order_qty]  = ord[:total_quantity]
      @gw.orders[oid][:order_type] = ord[:order_type]
      @gw.orders[oid][:limit_px]   = ord[:limit_price]
      @gw.orders[oid][:aux_px]     = ord[:aux_price]
      @gw.orders[oid][:tif]        = ord[:tif]
      @gw.orders[oid][:oca_group]  = ord[:oca_group]
      @gw.orders[oid][:oca_type]   = ord[:oca_type]
      @gw.orders[oid][:account]    = ord[:account]
      @gw.orders[oid][:open_close] = ord[:open_close]
      @gw.orders[oid][:order_ref]  = ord[:order_ref]

      if ord[:parent_id] == 0
        order_detail = parse_parent_order(con,ord,state)
        @gw.parent_orders[symbol] ||= []
        @gw.parent_orders[symbol] << order_detail
      else
        order_detail = parse_child_order(con,ord,state)
        @gw.child_orders[symbol] ||= {}
        @gw.child_orders[symbol][order_detail[:my_order_type]] ||= []
        @gw.child_orders[symbol][order_detail[:my_order_type]] << order_detail
      end

      @gw.all_orders[symbol] ||= {}
      @gw.all_orders[symbol]["StopEntry"] ||= {}
      @gw.all_orders[symbol]["LimitEntry"] ||= {}
      @gw.all_orders[symbol]["StopLoss"] ||= {}
      @gw.all_orders[symbol]["ProfitTgt"] ||= {}
      #@gw.all_orders[symbol]["StopEntry"] ||= []
      #@gw.all_orders[symbol]["StopLoss"] ||= []
      #@gw.all_orders[symbol]["ProfitTgt"] ||= []
      #puts "my_order_type=#{order_detail[:my_order_type]}"
      #@gw.all_orders[symbol][order_detail[:my_order_type]] << order_detail
      puts "symbol=#{symbol}"
      puts "oid=#{oid}"
      puts "order_detail=#{order_detail}"
      puts "oid=#{oid}"
      @gw.all_orders[symbol][order_detail[:my_order_type]][oid] = order_detail

      str = sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f%6.2f\n",order_detail[:my_order_type],order_detail[:parent_id],order_detail[:local_id],order_detail[:open_close],order_detail[:status],order_detail[:symbol],order_detail[:action],order_detail[:order_type],order_detail[:total_quantity],order_detail[:aux_price],order_detail[:limit_price]
      @fh_open_orders.write str
    }
    
    @ib.subscribe(:TickOptionComputation) { |msg| 
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect 
      tick_type_cnt[msg.data[:tick_type]] =+ 1
    }
    
    @ib.subscribe(:TickEFP)               { |msg| 
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      tick_type_cnt[msg.data[:tick_type]] =+ 1
    }
    
    @ib.subscribe(:AccountDownloadEnd) do |msg| 
      info "#{account_code}: AccountDownloadEnd msg=#{msg}"
      @fh_account_data.write "AccountDownloadEnd:: #{msg}\n"
    end
    
    md_subscriptions
    #md_subscriptions if @mkt_data_server

#    Signal.trap("INT") { warn "interrupted caught in EWrapper"; exit }
    
  end

  def md_subscriptions
    @ib.subscribe(:RealTimeBar) { |msg|
      tick_type_cnt[msg.data[:tick_type]] =+ 1
      routing_key = md_routing_key(Zts.conf.rt_bar5s, msg.data[:request_id])
      info msg.data
      market,sec_id = sec_master.decode_ticker(msg.data[:request_id])
      payload = msg.data[:bar].merge(mkt: market, sec_id: sec_id)
      @fh_rt_bars.write "#{payload}\n"
    }

    # market data subscriptions
    @ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) do |msg|
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.to_human
      #debug "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.inspect
      #ttype = IB::TICK_TYPES[msg.data[:tick_type]]
      ttype = msg.data[:tick_type]
      tid = msg.data[:ticker_id]
      case ttype
      when 0
        @gw.lvc[tid][:bid_size]  = msg.data[:size]
      when 1
        @gw.lvc[tid][:bid_price] = msg.data[:price]
        @gw.lvc[tid][:bid_size]  = msg.data[:size]
      when 2
        @gw.lvc[tid][:ask_price] = msg.data[:price]
        @gw.lvc[tid][:ask_size]  = msg.data[:size]
      when 3
        @gw.lvc[tid][:ask_size]  = msg.data[:size]
      when 4
        @gw.lvc[tid][:last_price] = msg.data[:price]
        @gw.lvc[tid][:last_size]  = msg.data[:size]
      when 5
        @gw.lvc[tid][:last_size]  = msg.data[:size]
      when 6
        @gw.lvc[tid][:high_price] = msg.data[:price]
        @gw.lvc[tid][:high_size]  = msg.data[:size]
      when 7
        @gw.lvc[tid][:low_price]      = msg.data[:price]
        @gw.lvc[tid][:low_size]       = msg.data[:size]
      when 8
        @gw.lvc[tid][:volume]         = msg.data[:size]
      when 9
        @gw.lvc[tid][:close_px]       = msg.data[:price]
        @gw.lvc[tid][:close_size]     = msg.data[:size]
      when 45
        @gw.lvc[tid][:last_timestamp] = msg.data[:value]
      end
      #@gw.print_tick(tid)

      #1	BID_PRICE	tickPrice()      # price, size
      #2	ASK_PRICE	tickPrice()      # price, size
      #4	LAST_PRICE	tickPrice()      # price, size
      #3	ASK_SIZE	tickSize()       # size
      #0	BID_SIZE	tickSize()       # size
      #5	LAST_SIZE	tickSize()       # size
      #8	VOLUME	tickSize()               # size
      #6	HIGH	tickPrice()              # price
      #7	LOW	tickPrice()              # price
      #9	CLOSE_PRICE	tickPrice()      # price
      #45      last_timestamp                   # value
      msg.data[:tick_type_str] = IB::TICK_TYPES[msg.data[:tick_type]]
      msg.data[:tkr] = @gw.sid_map[msg.data[:ticker_id]]

      @fh_tick_data.write "#{msg.data}\n"

      #payload = msg.data.to_json
      #@fh_tick_data.write "#{payload}\n"
    end

    #def print_lvc
    #  @lvc.keys.each { |tid| print_tick(tid) }
    #end

    #def print_tick(tid)
    #  print "#{@gw.sid_map[tid]} @lvc[#{tid}] = #{@lvc[tid]}\n"
    #  #print "%5.2f/%3d %5.2f/%3d %5.2%/%3d   %5.2f/3d  %5.2%/%3d  %5.2%/%3d  %6d\n".format(@lvc[tid][:bid_price],@lvc[tid][:bid_size],@lvc[tid][:ask_price],[tid][:ask_size],@lvc[tid][:last_price],@lvc[tid][:last_size], @lvc[tid][:high_price],@lvc[tid][:high_size],@lvc[tid][:low_price],@lvc[tid][:low_size],@lvc[tid][:volume],@lvc[tid][:close_px], @lvc[tid][:close_size],@lvc[tid][:last_timestamp])
    #end
  end
  
=begin
  def long?(tkr)
    debug "**********long?(#{tkr})"
    return false unless @gw.portf.key?(tkr)
    debug "**********@gw.portf.key?(tkr)=#{@gw.portf.key?(tkr)}"
    @gw.portf[tkr][:position] > 0
  end

  def short?(tkr)
    debug "**********short?(#{tkr})"
    return false unless @gw.portf.key?(tkr)
    debug "**********@gw.portf.key?(tkr)=#{@gw.portf.key?(tkr)}"
    @gw.portf[tkr][:position] < 0
  end
=end

  def parse_parent_order(con,ord,state)
    debug "*********************parse_parent_order"
    tkr = con[:symbol]
    @my_order_status[tkr] ||= {}
    my_order_type = ""
    if @gw.long?(tkr)
      debug "********** long"
      if ord[:action] == "SELL"
        puts "action == SELL"
        if ord[:order_type] == "STP"
          @my_order_status[tkr]['stop_loss'] = { 'tkr' => tkr,
                                                'stop_price' => ord[:aux_price],
                                                'order_qty' => ord[:total_quantity]
                                              }
          my_order_type = "StopLoss"
          debug "********** StopLoss"
        end
        if ord[:order_type] == "LMT"
          puts "order_type == LMT"
          my_order_type = "ProfitTgt"
          debug "********** ProfitTgt"
        end
      end
      if ord[:action] == "BUY"
        puts "action is #{ord[:action]}"
        puts "ord[:order_type]=#{ord[:order_type]}"
        if ord[:order_type] == "STP" or ord[:order_type] == "STP LMT"
          debug "order_type = #{ord[:order_type]}"
          my_order_type = "StopEntry"
          debug "********** StopEntry"
        elsif ord[:order_type] == "LMT"
          my_order_type = "LimitEntry"
          debug "********** LimitEntry"
        end
      end
    elsif @gw.short?(tkr)
      debug "********** short"
      if ord[:action] == "BUY" and ord[:order_type] == "STP"
        @my_order_status[tkr]['stop_loss'] = { 'tkr' => tkr,
                                              'stop_price' => ord[:aux_price],
                                              'order_qty' => ord[:total_quantity]
                                            }
        my_order_type = "StopLoss"
        debug "********** StopLoss"
      end
    else   # no position
      info "No Position for #{tkr}"
      info "action = #{ord[:action]}"
      #if ord[:action] == "BUY"
        debug "order_type = #{ord[:order_type]}"
        if ord[:order_type] == "STP" or ord[:order_type] == "STP LMT"
          my_order_type = "StopEntry"
          debug "********** StopEntry"
        elsif ord[:order_type] == "LMT"
          my_order_type = "LimitEntry"
          debug "********** LimitEntry"
        end
      #end
    end
    rtn = { :my_order_type  =>  my_order_type,
             :parent_id      => ord[:parent_id],
             :local_id       => ord[:local_id],
             :open_close     => ord[:open_close],
             :open_close     => ord[:open_close],
             :status         => state[:status],
             :symbol         => tkr,
             :action         => ord[:action],
             :order_type     => ord[:order_type],
             :total_quantity => ord[:total_quantity],
             :aux_price      => ord[:aux_price],
             :limit_price    => ord[:limit_price],
           }
    return rtn
  end

  def parse_child_order(con,ord,state)
    debug "********************parse_child_order"
    tkr = con[:symbol]
    @my_order_status[tkr] ||= {}
    my_order_type = ""
    if @gw.long?(tkr)
      debug "********** long"
      if ord[:action] == "SELL" and ord[:order_type] == "STP"
        @my_order_status[tkr]['stop_loss'] = { 'tkr' => tkr,
                                              'stop_price' => ord[:aux_price],
                                              'order_qty' => ord[:total_quantity]
                                            }
        my_order_type = "StopLoss"
        debug "********** StopLoss"
      end
      if ord[:action] == "SELL" and ord[:order_type] == "LMT"
        my_order_type = "ProfitTgt"
        debug "********** ProfitTgt"
      end
    elsif @gw.short?(tkr)
      debug "********** short"
      if ord[:action] == "BUY" and ord[:order_type] == "STP"
        @my_order_status[tkr]['stop_loss'] = { 'tkr' => tkr,
                                              'stop_price' => ord[:aux_price],
                                              'order_qty' => ord[:total_quantity]
                                            }
        my_order_type = "StopLoss"
        debug "********** StopLoss"
      end
    else   # no position
      debug "No Position for #{tkr}"
      debug "action = #{ord[:action]}"
      if ord[:order_type] == "STP" or ord[:order_type] == "STP LMT"
        my_order_type = "StopLoss"
        debug "********** StopLoss"
      end
      if ord[:order_type] == "LMT"
        my_order_type = "ProfitTgt"
        debug "********** ProfitTgt"
      end
    end
    return { :my_order_type  =>  my_order_type,
             :parent_id      => ord[:parent_id],
             :local_id       => ord[:local_id],
             :open_close     => ord[:open_close],
             :open_close     => ord[:open_close],
             :status         => state[:status],
             :symbol         => tkr,
             :action         => ord[:action],
             :order_type     => ord[:order_type],
             :total_quantity => ord[:total_quantity],
             :aux_price      => ord[:aux_price],
             :limit_price    => ord[:limit_price],
           }
  
  end

  private

  def debug(str)
    if @current_log_level >= @debug_level
      puts str
    end
  end

  def warn(str)
    if @current_log_level >= @warn_level
      puts str
    end
  end

  def info(str)
    if @current_log_level >= @info_level
      puts "INFO: " + str
    end
  end
end

