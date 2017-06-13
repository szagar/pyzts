#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require "amqp_factory"
require 'store_mixin'
require 'order_struct'
require "s_m"
#require "e_wrapper"
require "ib-ruby"
require "json"
require "my_config"
require 'configuration'
require 'mkt_subscriptions'
require "log_helper"

class IbGwSim
  include LogHelper
  include Store

  attr_reader :thread_id
  attr_reader :ib, :this_broker, :mkt_data_server
  attr_reader :sec_master

  def initialize(broker,opts={})
    show_info "IbGw#initialize"
    DaemonKit.logger.level = :info

    broker_config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      broker})
  
    @mkt_subs           = MktSubscriptions.instance
    @mkt_data_server    = broker_config.md_status == "true" ? true : false
    @mkt_data_server_id = broker_config.md_id
    puts "Ticker Plant #{@mkt_data_server_id} is #{@mkt_data_server ? 'on' : 'off'}"
 
    @contracts   = Hash.new
    @progname    = File.basename(__FILE__,".rb")
    @proc_name   = "ib_gateway-#{broker}"
    @this_broker = broker
    @local_subs  = {}
    @open_orders = {}

    @sec_master = SM.instance

    show_info "IB Gateway, program name : #{@progname}"
    show_info "            proc name    : #{@proc_name}"
    show_info "            broker       : #{this_broker}"
    show_info "            tkr plant    : #{@mkt_data_server_id} is #{mkt_data_server ? 'on' : 'off'}"

    show_info "Start EM thread"
    @thread_id = Thread.new { EventMachine.run }
    if defined?(JRUBY_VERSION)
     # on the JVM, event loop startup takes longer and .next_tick behavior
     # seem to be a bit different. Blocking current thread for a moment helps.
     sleep 0.5
    end

  end

  def amqp_setup
    connection, @channel = AmqpFactory.instance.channel
    md_connection, @md_channel = AmqpFactory.instance.md_channel
    @exchange        = @channel.topic(Zts.conf.amqp_exch_flow,
                                      Zts.conf.amqp_exch_options)
    @exchange_market = @md_channel.topic(Zts.conf.amqp_exch_mktdata,
                                        Zts.conf.amqp_exch_options)
  end
  
  def active_mkt_data_server?
    @mkt_data_server
  end

  def watch_for_new_orders
    debug "IbGwSim#watch_for_new_orders"
    routing_key = "#{Zts.conf.rt_submit}.#{this_broker}"
    #debug "exchange_order_flow = @channel.topic(#{Zts.conf.amqp_exch_flow}, #{Zts.conf.amqp_exch_options})"
    #@exchange = @channel.topic(Zts.conf.amqp_exch_flow,
    #                         Zts.conf.amqp_exch_options)

    show_info "order ->(#{@exchange.name}/#{routing_key})"
    @channel.queue("", :auto_delete => true)
           .bind(@exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|

      to_broker = headers.message_id
      show_info "to_broker = #{to_broker}"
      show_info "this_broker = #{this_broker}"
      #show_info "IB conn: #{ZtsApp::Config::IB[this_broker.to_sym].inspect}"
      place_order(JSON.parse(payload)) if ( to_broker == this_broker )
    end
  end

=begin
  def watch_for_md_unrequests
    routing_key = Zts.conf.rt_unreq_bar5s
    @exchange_md ||= @channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "md_unrequest ->(#{@exchange_md.name}/#{routing_key})"
    @channel.queue("", :auto_delete => true)
           .bind(@exchange_md, :routing_key => routing_key)
           .subscribe do |headers, payload|
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
      debug "watch_for_md_unrequests next"
    end
  end
=end

  def subscribe_admin
    routing_key = Zts.conf.rt_admin
    show_info "subscribe_admin: #{routing_key} on #{@exchange.name}"
    @channel.queue("", auto_delete: true)
           .bind(@exchange, routing_key: routing_key).subscribe do |hdr,payload|
      msg = JSON.parse(payload, :symbolize_names => true)
      command = msg[:command]
      params  = msg[:params]
      show_info "admin message: command = #{command}"
      show_info "admin message: params  = #{params}"
      begin
        self.send(command, params) if %W(query_account_data manual_fill).include? command 
      rescue => e
        warn "IbGw: Problem with admin msg: #{payload}"
        warn e.message
      end
    end
  end

=begin
  def watch_for_md_requests
    queue_name = routing_key = Zts.conf.rt_req_bar5s
    exchange = @channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "md_req ->(#{exchange.name}/#{routing_key})"
    @channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
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
  end
=end

  def start_ewrapper
    puts "start_ewrapper: DO NOTHING for Simulator"
    #Fiber.new {
    #  ew = EWrapper.new(@ib,this_broker)
    #  ew.run
    #}.resume
  end

  def query_account_data(params=nil)
    show_info "query_account_data: DO NOTHING"
  end

  def subscribe_md_bar5s
    routing_key = "#{Zts.conf.rt_bar5s}.#.#"
    show_info "IbGwSim#subscribe_md_bar5s: subscribe:(#{@exchange_market.name}/#{routing_key})"
    @md_channel.queue("", auto_delete: true)
              .bind(@exchange_market, routing_key: routing_key)
              .subscribe do |hdr,msg|
      print "*"
      puts msg
      hdr.routing_key[/md.bar.5sec\.(.*)\.(.*)/]
      #mkt,sec_id = [$1, $2]
      bar_data = JSON.parse(msg, :symbolize_names => true)
      check_open_orders(bar_data)
    end
    show_info "subscribed"
  end

  ###########
  private
  ###########

  def manual_fill(parms=nil)
  #def manual_fill(pos_id,qty,price,action,commission)
    #action = "buy" or "sell"
    pos_id     = parms[:pos_id]
    qty        = parms[:qty].to_i
    price      = parms[:price].to_f
    action     = parms[:action]
    commission = parms[:commission].to_f

    fill = FillStruct.from_hash( { pos_id:       pos_id,
                                   price:        price,
                                   avg_price:    price,
                                   quantity:     qty,
                                   commission:   commission,
                                   action:       action,
                                   broker:       @this_broker }
                               )
    show_info "Manual Fill: #{fill}"
    routing_key = Zts.conf.rt_fills
    exchange = @channel.topic(Zts.conf.amqp_exch_flow,
                             Zts.conf.amqp_exch_options)
    show_info "<-(#{exchange.name}/#{routing_key}/#{pos_id}): (#{fill.attributes})"
    exchange.publish(fill.attributes.to_json, :routing_key => routing_key, :message_id => pos_id, :persistent => true)

    send_order_status("Filled",order) if order["quantity"] == 0
  
  end

  def create_fill(order,bar)
    puts "IbGwSim#create_fill: order=#{order}"
    puts "IbGwSim#create_fill: bar=#{bar}"
    qty = [bar[:volume].to_i,order["quantity"].to_i].min
    order["filled"] += qty
    order["quantity"] -= qty
    order["avg_price"] = bar[:close]
    pos_id = order["order_ref"]
    action = (order["side"] == "B") ? "buy" : "sell"
    fill = FillStruct.from_hash( { pos_id:       pos_id,
                                   price:        bar[:close].to_f,
                                   avg_price:    order["avg_price"],
                                   quantity:     qty.to_i,
                                   commission:   0.0,
                                   action:       action,
                                   broker:       @this_broker }
                               )
    show_info "Fill: #{fill}"
    routing_key = Zts.conf.rt_fills
    exchange = @channel.topic(Zts.conf.amqp_exch_flow,
                             Zts.conf.amqp_exch_options)
    show_info "<-(#{exchange.name}/#{routing_key}/#{pos_id}): (#{fill.attributes})"
    exchange.publish(fill.attributes.to_json, :routing_key => routing_key, :message_id => pos_id, :persistent => true)

    send_order_status("Filled",order) if order["quantity"] == 0
  end
  
  def send_order_status(status,order)
    data = { "broker_ref" => order["order_ref"],
             "pos_id"     => order["order_ref"],
             "local_id"   => order["order_ref"],
             "status"     => status,
             "filled"     => order["filled"],
             "remaining"  => 0,
             "average_fill_price" => order["avg_price"],
             "perm_id"            => "tbd",
             "parent_id"          => 0,
             "last_fill_price"    => order["avg_price"],
             "client_id"          => 0,
             "why_held"           => "",
           }
    routing_key = Zts.conf.rt_order_status
    @exchange.publish(data.to_json, :routing_key => routing_key, :persistent => true)
  end

  def check_open_orders(bar)
    debug "check_open_orders(#{bar})"
    sec_id = bar[:sec_id]
    debug "check_open_orders: sec_id=#{sec_id}/#{sec_id.class}"
    @open_orders.each do |k,o_arr|
      debug "check_open_orders: Order for sid #{k}"
      o_arr.each do |o|
        debug "#{o["side"]} #{o["symbol"]} @#{o["limit_price"]} pos_id:#{o["order_ref"]} filled:#{o["filled"]}/#{o["quantity"]}@#{o["avg_price"]}"
      end
    end
    debug "check_open_orders: sec_id:#{sec_id} not in @open_orders" unless @open_orders.has_key?(sec_id)
    return unless @open_orders.has_key?(sec_id)
    close  = bar[:close].to_f
    @open_orders[sec_id].each do |order|
      debug "check_open_orders: sec_id:#{sec_id} side:#{order["side"]} qty:#{order["quantity"]} lmt:#{order['limit_price']} close:#{close}"
      debug "check_open_orders: sec_id:#{sec_id} not in @open_orders" unless @open_orders.has_key?(sec_id)
      #next unless(order["side"] == "B" && order["quantity"] > 0)
      next unless(order["quantity"] > 0)
      debug "check_open_orders: order = #{order}"
      lmt_px = order['limit_price'].to_f
      next unless (order["side"] == "B" && close <= lmt_px) ||
                  (order["side"] == "S" && close >= lmt_px)
      qty = [bar[:volume].to_i,order["quantity"].to_i].min
      create_fill(order,bar)
    end
  end

  def place_order(order_hash)
    debug "place_order: order_hash=#{order_hash}"
    order = OrderStruct.from_hash(order_hash)
    puts "ib_gw: order attributes: #{order.attributes}"
    puts "contract = get_contract( #{order.mkt}, #{order.sec_id} )"
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
    #info ib_order
    puts ib_order

    order_att = ib_order.attributes
    order_att.merge!(contract.attributes)
    order_att.merge!(filled: 0)
    puts "IbGwSim#place_order: order_att = #{order_att}"
    sec_id = order['sec_id'].to_s
    @open_orders[sec_id] ||= []
    @open_orders[sec_id] << order_att
    puts "place_order: @open_orders=#{@open_orders}"
    @open_orders.each do |k,o_arr|
      debug "place_order: Order for sid #{k}"
      o_arr.each do |o|
        debug "#{o["side"]} #{o["quantity"]} #{o["symbol"]} @#{o["limit_price"]} pos_id:#{o["order_ref"]} filled:#{o["filled"]}@#{o["avg_price"]}"
      end
    end
  end

=begin
  def place_order(sec_id, ib_order, contract)
    puts "place_order(#{ib_order}, #{contract})"
    debug "place_order: #{ib_order}"
    debug "place_order: #{contract}"
    order = ib_order.attributes
    order.merge!(contract.attributes)
    puts "IbGwSim#place_order: order = #{order}"
    sec_id = order['sec_id']
    @open_orders[sec_id] ||= []
    @open_orders[sec_id] << order
  end
=end

  def get_ticker_id(mkt, sec_id)
    sec_master.encode_ticker(mkt, sec_id)
  end

  def get_contract( mkt, sec_id )
    show_info "get_contract( #{mkt}, #{sec_id} )"
    tkr_id = get_ticker_id(mkt, sec_id)
    if @contracts.member?(tkr_id) then
      return @contracts[tkr_id]
    else
      show_info "data = sec_master.send(#{mkt}_indics,#{sec_id})"
      data = sec_master.send("#{mkt}_indics",sec_id)
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

  def req_md(ticker_id, contract)
    debug "req_md(#{ticker_id}, #{contract.inspect})"
    #show_info "req_md:Market Data Request: ticker_id=#{ticker_id} on #{@mkt_data_server_id}"

    #@mkt_subs.activate(ticker_id,@mkt_data_server_id)
    #show_action "@ib.send_message :RequestRealTimeBars, :ticker_id => #{ticker_id}, contract => #{contract}"
    #@local_subs[ticker_id] = :on
    #@ib.send_message IB::Messages::Outgoing::RequestRealTimeBars.new(
    #                  :request_id => ticker_id,
    #                  :contract => contract,
    #                  :data_type => :trades,
    #                  :bar_size => 5, # Only 5 secs bars available?
    #                  :use_rth => true)
  end

  def unreq_md( ticker_id )
    return
    if ticker_id == "all"
      @local_subs.keys.each { |id| debug "@ib.send_message :CancelRealTimeBars, :id => #{id}" }
      @local_subs.keys.each { |id| @ib.send_message :CancelRealTimeBars, :id => id
                              @local_subs.delete(id)
                       }
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
