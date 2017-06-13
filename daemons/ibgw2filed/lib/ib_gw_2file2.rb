#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require 'store_mixin'
require 'order_struct'
require "s_m"
require "e_wrapper_2file"
require "ib-ruby"
require "json"
require "my_config"
require 'configuration'
require 'mkt_subscriptions'
require "log_helper"

#    @thread_id = Thread.new {
#      EventMachine::run {
#        EventMachine::start_server "127.0.0.1", 8081, IbGw
#        puts 'running echo server on 8081'
#      }
#    }


class IbGw
  include LogHelper
  include Store

  attr_reader :thread_id
  attr_reader :ib, :mkt_data_server

  def initialize(broker,opts={})
    show_info "IbGw#initialize"
    DaemonKit.logger.level = :info

    puts "Broker is #{broker}"
    broker_config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      broker})
  
    @this_broker = broker
    @mkt_subs           = MktSubscriptions.instance
    @mkt_data_server    = broker_config.md_status == "true" ? true : false
    @mkt_data_server_id = broker_config.md_id
    puts "Ticker Plant #{@mkt_data_server_id} is #{@mkt_data_server ? 'on' : 'off'}"
 
    ib_app = opts[:ib_app] ||= "gw"
    port   = broker_config.send("#{ib_app}_port")
    puts "@ib = IB::Connection.new :host      => #{broker_config.host}, \
                                   :client_id => #{broker_config.client_id}, \
                                   :port      => #{port}"
    @ib = IB::Connection.new(:host      => broker_config.host,
                             :client_id => broker_config.client_id,
                             :port      => port)

    puts "@ib=#{@ib}"
    @ib.wait_for :NextValidId
 
    @contracts   = Hash.new
    @progname    = File.basename(__FILE__,".rb")
    @proc_name   = "ib_gateway-#{broker}"
    @local_subs  = {}

    @sec_master = SM.instance

    show_info "IB Gateway, program name : #{@progname}"
    show_info "            proc name    : #{@proc_name}"
    show_info "            tkr plant    : #{@mkt_data_server_id} is #{mkt_data_server ? 'on' : 'off'}"

    #show_info "Start EM thread"
    #@thread_id = Thread.new { EventMachine.run }
    if defined?(JRUBY_VERSION)
     # on the JVM, event loop startup takes longer and .next_tick behavior
     # seem to be a bit different. Blocking current thread for a moment helps.
     sleep 0.5
    end

  end

  def post_init
    puts "-- someone connected to the echo server!"
  end

  def receive_data data
    puts "FOT IT ******************************** #{data}\n"
    command,args = data.chomp.split
    case command.downcase
    when "init"
      subscribe_ticks(args[0])
    end
    send_data ">>> you sent: #{data}  command: #{command}  args: #{args}"
  end
  def active_mkt_data_server?
    @mkt_data_server
  end

  def watch_for_new_orders
    return
    order_hash = JSON.parse(payload)
    $stderr.puts "order_hash=#{order_hash}"
    order = OrderStruct.from_hash(order_hash)
    $stderr.puts "ib_gw: order attributes: #{order.attributes}"
    $stderr.puts "contract = get_contract( #{order.mkt}, #{order.sec_id} )"
    contract = get_contract( order.mkt, order.sec_id )
    action = order.action.upcase

    puts "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
                              "limit_price: #{order.limit_price || 0}," \
                              "action:"" #{action}," \
                              "order_type => #{order.price_type}," \
                              "order_ref: #{order.pos_id}"

    show_info "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
                              "limit_price: #{order.limit_price || 0}," \
                              "action:"" #{action}," \
                              "order_type => #{order.price_type}," \
                              "order_ref: #{order.pos_id}"
    ib_order = IB::Order.new :total_quantity => order.order_qty.to_i,
                              :limit_price => order.limit_price || 0,
                              :action => action,
                              :order_type => order.price_type,
                              :order_ref => order.pos_id
    puts ib_order

    place_order ib_order, contract
  end

  def watch_for_md_unrequests
    debug "mktdta monitor unreq: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
    rec = JSON.parse(payload)
    debug "rec=#{rec.inspect}(#{rec.class})"
    sec_id = rec["sec_id"]
    if sec_id == "all"
      unreq_md(sec_id)
    else
      mkt    = rec['mkt']
      force = rec['force'] || false
      contract = get_contract( mkt, sec_id )
      debug "contract: #{contract.inspect}"
      show_info "market data unrequest: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
      tkr_id = get_ticker_id( mkt, sec_id ) rescue return
      unreq_md(tkr_id)
    end
  end

  def subscribe_admin
    #msg = JSON.parse(payload, :symbolize_names => true)
    #command = msg[:command]
    #params  = msg[:params]
    #show_info "admin message: command = #{command}"
    #show_info "admin message: params  = #{params}"
    #begin
    #  self.send(command, params) if %W(query_account_data).include? command 
    #rescue => e
    #  warn "IbGw: Problem with admin msg: #{payload}"
    #  warn e.message
    #end
  end

  def subscribe_ticks(tkr)
    mkt = 'stock'
    sec_id = @sec_master.tkr_lookup(mkt, tkr)
    contract = get_contract( mkt, sec_id )
    debug "subscribe_ticks: contract: #{contract.inspect}"

    tkr_id = get_ticker_id( mkt, sec_id ) rescue return
    req_ticks(tkr_id, contract)
  end

  def watch_for_md_requests
    debug "watch_for_md_requests: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
    rec = JSON.parse(payload)
    debug "rec=#{rec.inspect}(#{rec.class})"
    sec_id = rec["sec_id"]
    mkt    = rec['mkt']
    action = rec['action']
    force = rec['force'] || false
    contract = get_contract( mkt, sec_id )
    debug "contract: #{contract.inspect}"
    show_info "market data request: action:#{action}  #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
    tkr_id = get_ticker_id( mkt, sec_id ) rescue return
    case action.downcase
      when "on"
        req_md(tkr_id, contract) if ((not @mkt_subs.bar5s_active?(tkr_id)) || force)
      when "off"
        unreq_md(tkr_id)
      else
        puts "Market data request action(#{action}) NOT known"
    end
  end

  def start_ewrapper
    Fiber.new {
      ew = EWrapper.new(@ib,@this_broker)
      ew.run
    }.resume
  end

  def query_account_data(params=nil)
    show_action "ib.send_message :RequestAccountData"
    ib.send_message :RequestAccountData
    #ib.wait_for :AccountDownloadEnd
  end

  ###########
  private
  ###########

  def place_order(ib_order, contract)
    $stderr.puts "place_order(#{ib_order}, #{contract})"
    debug "place_order: #{ib_order}"
    debug "place_order: #{contract}"
    @ib.wait_for :NextValidId
    attr = ib_order.attributes
    show_info "Place Order(pos_id:#{attr['order_ref']}):  #{attr['side']} #{attr['quantity']} "\
                "#{contract.attributes['symbol']}@#{attr['limit_price']} #{attr['order_type']} (#{attr['open_close']})"
    ib_order_id = @ib.place_order ib_order, contract
    show_info "Order Placed (IB order number = #{ib_order_id})"
    #ib.send_message :RequestAllOpenOrders
  end

  def get_ticker_id(mkt, sec_id)
    @sec_master.encode_ticker(mkt, sec_id)
  end

  def get_contract( mkt, sec_id )
    show_info "get_contract( #{mkt}, #{sec_id} )"
    tkr_id = get_ticker_id(mkt, sec_id)
    if @contracts.member?(tkr_id) then
      return @contracts[tkr_id]
    else
      show_info "data = @sec_master.send(#{mkt}_indics,#{sec_id})"
      data = @sec_master.send("#{mkt}_indics",sec_id)
      #debug "mkt=#{mkt}"
      sec_exchange = 'SMART'
      sec_exchange = data['exchange'] if (mkt == :index)
      show_info "@contracts[tkr_id] = IB::Contract.new(:symbol => #{data['ib_tkr']},"
      show_info "                                     :currency => USD,"
      #show_info "                                     :sec_type => 'STK',"
      show_info "                                     :sec_type => :stock,"
      show_info "                                     :exchange => #{sec_exchange},"
      show_info "                                     :description => #{data['desc']})"
      @contracts[tkr_id] = IB::Contract.new(:symbol => data['ib_tkr'],
                                           :currency => "USD",
                                           #:sec_type => 'STK',  #mkt,
                                           :sec_type => :stock,  #mkt,
                                           :exchange => sec_exchange,
                                           :description => data['desc'])
    end
  end

  def req_ticks(ticker_id,contract)
    #msg = IB::OutgoingMessages::RequestMarketData.new({
    #                                                  :ticker_id => id,
    #                                                  :contract => contract
    #                                                })
    #ib.dispatch(msg)
    @ib.send_message IB::Messages::Outgoing::RequestMarketData.new(
                        :request_id => ticker_id,
                        :contract => contract)
  end

  def req_md(ticker_id, contract)
    debug "req_md(#{ticker_id}, #{contract.inspect})"
    show_info "req_md:Market Data Request: ticker_id=#{ticker_id} on #{@mkt_data_server_id}"

#    unless @mkt_subs.is_active?(ticker_id)
    @mkt_subs.activate(ticker_id,@mkt_data_server_id)
    show_action "@ib.send_message :RequestRealTimeBars, :ticker_id => #{ticker_id}, contract => #{contract}"
    @local_subs[ticker_id] = :on
    #@ib.send_message :RequestRealTimeBars, :ticker_id => ticker_id, :contract => contract, \
    #                 :data_type => "TRADES", :bar_size => "5 secs"
    @ib.send_message IB::Messages::Outgoing::RequestRealTimeBars.new(
                        :request_id => ticker_id,
                        :contract => contract,
                        :data_type => :trades,
                        :bar_size => 5, # Only 5 secs bars available?
                        :use_rth => true)
      #  data = { :id => ticker_id (int),
      #           :contract => Contract ,
      #           :bar_size => int/Symbol? Currently only 5 second bars are supported,
      #                        if any other value is used, an exception will be thrown.,
      #           :data_type => Symbol: Determines the nature of data being extracted.
      #                       :trades, :midpoint, :bid, :ask, :bid_ask,
      #                       :historical_volatility, :option_implied_volatility,
      #                       :option_volume, :option_open_interest
      #                       - converts to "TRADES," "MIDPOINT," "BID," etc...
      #          :use_rth => int: 0 - all data available during the time span requested
      #                     is returned, even data bars covering time intervals where the
      #                     market in question was illiquid. 1 - only data within the
      #                     "Regular Trading Hours" of the product in question is returned,
      #                     even if the time span requested falls partially or completely
      #                     outside of them.

      # ib.send_message IB::Messages::Outgoing::RequestRealTimeBars.new(
      #                  :request_id => request_id,
      #                  :contract => contract,
      #                  :bar_size => 5, # Only 5 secs bars available?
      #                  :data_type => :trades,
      #                  :use_rth => true)

#    end
  end

  def unreq_md(ticker_id)
    #tkr_plant = redis.hget("md:status:#{ticker_id}", "ticker_plant")
    if ticker_id == "all" then
      @local_subs.keys.each { |id| debug "@ib.send_message :CancelRealTimeBars, :id => #{id}" }
      @local_subs.keys.each { |id| @ib.send_message :CancelRealTimeBars, :id => id
                              @local_subs.delete(id) }
    else
      tkr_plant = @mkt_subs.ticker_plant(ticker_id)
      debug "unreq_md(#{ticker_id}) mkt_data_server_id=#{@mkt_data_server_id}   tkr_plant=#{tkr_plant}"
      if (@mkt_data_server_id == tkr_plant) then
        debug "unreq_md(#{ticker_id})"
        show_info "unreq_md:Market Data UnRequest: ticker_id=#{ticker_id} on #{@mkt_data_server_id}"

        begin
          debug "@ib.send_message :CancelRealTimeBars, :id => #{ticker_id}"
          @ib.send_message :CancelRealTimeBars, :id => ticker_id

          debug "@local_subs.delete(#{ticker_id})"
          @local_subs.delete(ticker_id)
          #@mkt_subs.unsubscribe(ticker_id, "bar5s")
        rescue => e
          warn "Problem with CancelRealTimeBars"
          warn e.message
        end
      else
        $stderr.puts "Could not Cancel MktData for #{ticker_id}/#{tkr_plant} on #{@mkt_data_server_id}"
      end
    end
  end
end
