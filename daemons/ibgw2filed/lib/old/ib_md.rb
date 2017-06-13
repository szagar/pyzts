#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require "amqp_factory"
require 'store_mixin'
require 'order_struct'
require "s_m"
require "e_wrapper_md"
require "ib-ruby"
require "json"
require "my_config"
require 'configuration'
require 'mkt_subscriptions'
require "log_helper"

class IbMd
  include LogHelper
  include Store

  attr_reader :channel
  attr_reader :exchange_order_flow, :exchange_market
  attr_reader :thread_id
  attr_reader :ib, :this_broker, :mkt_data_server_id, :mkt_data_server
  attr_reader :sec_master, :mkt_subs

  def initialize(broker,opts={})
    show_info "IbMd#initialize"
    DaemonKit.logger.level = :info

    config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      broker})
  
    @mkt_subs           = MktSubscriptions.instance
    @mkt_data_server    = config.md_status == "true" ? true : false
    @mkt_data_server_id = config.md_id
    puts "Ticker Plant #{@mkt_data_server_id} is #{@mkt_data_server ? 'on' : 'off'}"
 
    ib_app = opts[:ib_app] ||= "gw"
    port   = config.send("#{ib_app}_port")
    puts "@ib = IB::Connection.new :host      => #{config.host}, \n",
         "                         :client_id => #{config.md_client_id}, \n",
         "                         :port      => #{port}"
    @ib = IB::Connection.new(:host      => config.host,
                             :client_id => config.md_client_id,
                             :port      => port)

    puts "@ib=#{@ib}"
    @ib.wait_for :NextValidId
 
    @contracts   = Hash.new
    @progname    = File.basename(__FILE__,".rb")
    @proc_name   = "ib_mktdata-#{broker}"
    @this_broker = broker

    @sec_master = SM.instance

    show_info "IB MD, program name : #{@progname}"
    show_info "            proc name    : #{@proc_name}"
    show_info "            broker       : #{this_broker}"
    show_info "            tkr plant    : #{mkt_data_server_id} is #{mkt_data_server ? 'on' : 'off'}"

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
    @exchange_order_flow = channel.topic(Zts.conf.amqp_exch_flow,
                                         Zts.conf.amqp_exch_options)
    @exchange_market     = channel.topic(Zts.conf.amqp_exch_mktdata,
                                         Zts.conf.amqp_exch_options)
  end
  
  def active_mkt_data_server?
    @mkt_data_server
  end

  def watch_for_md_unrequests
    routing_key = Zts.conf.rt_unreq_bar5s
    exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "md_unrequest ->(#{exchange.name}/#{routing_key})"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      debug "mktdta monitor unreq: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
      rec = JSON.parse(payload)
      debug "rec=#{rec.inspect}(#{rec.class})"
      sec_id = rec["sec_id"]
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
    routing_key = Zts.conf.rt_admin
    show_info "subscribe_admin: #{routing_key} on #{exchange_order_flow.name}"
    channel.queue("", auto_delete: true)
           .bind(exchange_order_flow, routing_key: routing_key).subscribe do |hdr,payload|
      msg = JSON.parse(payload, :symbolize_names => true)
      command = msg[:command]
      params  = msg[:params]
      show_info "admin message: command = #{command}"
      show_info "admin message: params  = #{params}"
      begin
        self.send(command, params) if %W(query_account_data).include? command 
      rescue => e
        warn "IbMd: Problem with admin msg: #{payload}"
        warn e.message
      end
    end
  end

  def watch_for_md_requests
    queue_name = routing_key = Zts.conf.rt_req_bar5s
    exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "md_req ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      debug "mktdta monitor req: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
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
          req_md(tkr_id, contract) if ((not mkt_subs.bar5s_active?(tkr_id)) || force)
        when "off"
          unreq_md(tkr_id)
        else
          puts "Market data request action(#{action}) NOT known"
        end
    end
  end

  def start_ewrapper
    Fiber.new {
      ew = EWrapperMd.new(@ib,this_broker)
      ew.run
    }.resume
  end

  ###########
  private
  ###########

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
      show_info "                                     :sec_type => 'STK',"
      show_info "                                     :exchange => #{sec_exchange},"
      show_info "                                     :description => #{data['desc']})"
      @contracts[tkr_id] = IB::Contract.new(:symbol => data['ib_tkr'],
                                           :currency => "USD",
                                           :sec_type => 'STK',  #mkt,
                                           :exchange => sec_exchange,
                                           :description => data['desc'])
    end
  end

  def req_md( ticker_id, contract )
    debug "req_md(#{ticker_id}, #{contract.inspect})"
    show_action "req_md:Market Data Request: ticker_id=#{ticker_id}"

    mkt_subs.add_sid(ticker_id)

    @ib.send_message :RequestRealTimeBars, :ticker_id => ticker_id, :contract => contract,
             :data_type => "TRADES", :bar_size => "5 secs"
    mkt_subs.subscribe(ticker_id,mkt_data_server_id,"bar5s")
  end

  def unreq_md( ticker_id )
    debug "unreq_md(#{ticker_id})"
    tkr_plant = mkt_subs.ticker_plant(ticker_id)
    if (mkt_data_server_id == tkr_plant) then
      show_action "Market Data UnRequest: ticker_id=#{ticker_id}"

      mkt_subs.rm_sid(ticker_id)
      mkt_subs.unsubscribe(ticker_id, "bar5s")

      @ib.send_message :CancelRealTimeBars, :id => ticker_id
    else
      show_info "Could not Cancel MktData for #{ticker_id}/#{tkr_plant} on #{mkt_data_server_id}"
    end
  end

end
