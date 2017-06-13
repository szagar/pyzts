#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require 'screen'
require 'redis_factory'
require 'order_struct'
require "s_m"
require "e_wrapper_bunny"
require "zts_config"
require "ib-ruby"
require "amqp_factory"
require "json"
require 'adminable'
#require 'zts_logger'
#require 'simple_logger'
require 'configuration'
require 'mkt_subscriptions'

#Screen.clear

class MyIb
  include Adminable
  include SimpleLogger
  attr_accessor :a, :ib, :account_code, :progname, :this_broker
  attr_accessor :exchange
  attr_accessor :proc_name, :redis
  
  attr_reader :ib, :mkt_data_server, :mkt_data_server_id

  AccountAlias = { 'DU95153' => 'ib_paper' }

  def initialize(broker, opts={})
    config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      broker})
    @this_broker        = broker
    @mkt_subs           = MktSubscriptions.instance
    @mkt_data_server    = config.md_status == "true" ? true : false
    @mkt_data_server_id = config.md_id
    show_info "Ticker Plant #{mkt_data_server_id} is #{@mkt_data_server ? 'on' : 'off'}"

    ib_app = opts[:ib_app] ||= "gw"
    port   = config.send("#{ib_app}_port")
    show_info "@ib = IB::Connection.new :host      => #{config.host}, \
                                   :client_id => #{config.client_id}, \
                                   :port      => #{port}"
    @ib = IB::Connection.new(:host      => config.host,
                             :client_id => config.client_id, 
                             :port      => port)
                             
    show_info "@ib=#{@ib}"
    @ib.wait_for :NextValidId
                         

    @contracts = Hash.new
    @progname = File.basename(__FILE__,".rb") 
    @proc_name = "ib_gateway-#{broker}"
    
    
    @redis = RedisFactory.instance.client
    
    show_info "progname=#{progname}"
    #simpleLoggerSetup(proc_name)
    
    show_info "IB Gateway, program name : #{progname}"
    show_info "            proc name    : #{proc_name}"    
    show_info "            broker       : #{this_broker}"    
  end
  
  def clear
    write_hdr
  end
  
  def alert(str)
    talk str
    warn str
  end
  
  def place_order(ib_order, contract)
    $stderr.puts "place_order(#{ib_order}, #{contract})"
    debug "place_order: #{ib_order}"
    debug "place_order: #{contract}"
    @ib.wait_for :NextValidId
    attr = ib_order.attributes
    info "Place Order(pos_id:#{attr['order_ref']}):  #{attr['side']} #{attr['quantity']} "\
                "#{contract.attributes['symbol']}@#{attr['limit_price']} #{attr['order_type']} (#{attr['open_close']})"
    ib_order_id = @ib.place_order ib_order, contract
    info "Order Placed (IB order number = #{ib_order_id})"
    #ib.send_message :RequestAllOpenOrders
  end

  def get_ticker_id(mkt, sec_id)
    SM.encode_ticker(mkt, sec_id)
  end
  
  def get_contract( mkt, sec_id )
    tkr_id = get_ticker_id(mkt, sec_id)
    if @contracts.member?(tkr_id) then
      return @contracts[tkr_id]
    else
      #debug "data = SM.send(#{mkt}_indics,#{sec_id})"
      data = SM.send("#{mkt}_indics",sec_id)
      #debug "mkt=#{mkt}"
      sec_exchange = 'SMART'
      sec_exchange = data['exchange'] if (mkt == :index)
      @contracts[tkr_id] = IB::Contract.new(:symbol => data['ib_tkr'],
                                           :currency => "USD",
                                           :sec_type => 'STK',  #mkt,
                                           :exchange => sec_exchange,
                                           :description => data['desc'])
    end
  end
  
  def set_md_status(ticker_id,status)
    case status
    when "InActive"
      redis.del "md:status:#{ticker_id}"
    else
      redis.hset "md:status:#{ticker_id}", "status", status
      redis.hset "md:status:#{ticker_id}", "ticker_plant", mkt_data_server_id
    end
  end
  
  def bar5s_active(ticker_id)
    (redis.hget("md:status:#{ticker_id}", "status")  == "bar5s")
  end

  def req_md( ticker_id, contract )
    debug "req_md(#{ticker_id}, #{contract.inspect})"
    info "MyIb#req_md:Market Data Request: ticker_id=#{ticker_id}"
    
    @mkt_subs.add_sid(ticker_id)

    @ib.send_message :RequestRealTimeBars, :ticker_id => ticker_id, :contract => contract, 
             :data_type => "TRADES", :bar_size => "5 secs"
    set_md_status(ticker_id,"bar5s")
  end
  
  def unreq_md( ticker_id )
    tkr_plant = redis.hget("md:status:#{ticker_id}", "ticker_plant")
    if (mkt_data_server_id == tkr_plant) then
      debug "unreq_md(#{ticker_id})"
      info "Market Data UnRequest: ticker_id=#{ticker_id}"
    
      @mkt_subs.rm_sid(ticker_id)

      @ib.send_message :CancelRealTimeBars, :id => ticker_id
      set_md_status(ticker_id,"InActive")
    else
      $stderr.puts "Could not Cancel MktData for #{ticker_id}/#{tkr_plant} on #{this_tkr_plant}"
    end
  end
  

  def query_account_data
    ib.send_message :RequestAccountData
    #ib.wait_for :AccountDownloadEnd
  end
  
  def watch_for_new_orders(channel)
    routing_key = "#{Zts.conf.rt_submit}.#{this_broker}"
    exchange = channel.topic(Zts.conf.amqp_exch_flow,
                             Zts.conf.amqp_exch_options)
    
    puts "order ->(#{exchange.name}/#{routing_key})"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|

      to_broker = headers.message_id
      info "to_broker = #{to_broker}"
      info "this_broker = #{this_broker}"
      info "IB conn: #{ZtsApp::Config::IB[this_broker.to_sym].inspect}"
      if ( to_broker == this_broker ) then
        order_hash = JSON.parse(payload)
        $stderr.puts "order_hash=#{order_hash}"
        order = OrderStruct.from_hash(order_hash)
        $stderr.puts "my_ib: order attributes: #{order.attributes}"
        $stderr.puts "contract = get_contract( #{order.mkt}, #{order.sec_id} )"
        contract = get_contract( order.mkt, order.sec_id )
        action = order.action.upcase

        puts "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
                              "limit_price: #{order.limit_price || 0}," \
                              "action:"" #{action}," \
                              "order_type => #{order.price_type}," \
                              "order_ref: #{order.pos_id}"
        
        info "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
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
              
        place_order ib_order, contract
      end
    end
  end
  
  def watch_for_md_unrequests(channel)
    routing_key = Zts.conf.rt_unreq_bar5s
    exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "setup ->(#{exchange.name}/#{routing_key})"
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
      info "market data unrequest: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
      tkr_id = get_ticker_id( mkt, sec_id ) rescue return
      unreq_md(tkr_id)
    end
  end

  def watch_for_md_requests(channel)
    queue_name = routing_key = Zts.conf.rt_req_bar5s
    exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      debug "mktdta monitor req: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
      rec = JSON.parse(payload)
      debug "rec=#{rec.inspect}(#{rec.class})"
      sec_id = rec["sec_id"]
      mkt    = rec['mkt']
      force = rec['force'] || false
      contract = get_contract( mkt, sec_id )
      debug "contract: #{contract.inspect}"
      info "market data request: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
      tkr_id = get_ticker_id( mkt, sec_id ) rescue return
      case rec['action'].downcase
        when "on"
          req_md(tkr_id, contract) if ((not bar5s_active(tkr_id)) || force)
        when "off"
          unreq_md(tkr_id)
        else
          puts "Market data request action(#{rec['action']}) NOT known"
        end        
    end
  end
  
=begin
  def watch_for_account_requests(channel)
    queue_name = routing_key = ZtsApp::Config::ROUTE_KEY[:request][:acctData]
    exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                             Zts.conf.amqp_exch_options)
    show_info "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      puts "query_account_data"
      query_account_data
    end
  end
=end
  
  def run
#    puts "@ib = IB::Connection.new :host => #{ZtsApp::Config::IB[this_broker.to_sym][:conn][:host]}," \
#                              ":client_id => #{ZtsApp::Config::IB[this_broker.to_sym][:conn][:client_id]}," \
#                             ":port => #{ZtsApp::Config::IB[this_broker.to_sym][:conn][:port]}"
#    
#    @ib = IB::Connection.new :host => ZtsApp::Config::IB[this_broker.to_sym][:conn][:host],
#                             :client_id => ZtsApp::Config::IB[this_broker.to_sym][:conn][:client_id], 
#                             :port => ZtsApp::Config::IB[this_broker.to_sym][:conn][:port]
#                             
#    @ib.wait_for :NextValidId
                         
    t1 = Thread.new { EventMachine.run }
    if defined?(JRUBY_VERSION)
     # on the JVM, event loop startup takes longer and .next_tick behavior
     # seem to be a bit different. Blocking current thread for a moment helps.
     sleep 0.5
    end

    puts "start EM"
    EventMachine.next_tick do
      connection, channel = AmqpFactory.instance.channel
      
      watch_admin_messages(channel)
      ignore_admin_all

      Fiber.new {
        ew=EWrapper.new(@ib,self)
        ew.run
      }.resume
      # Subscribers
##      stop_t2 = false
#      t2 = Thread.new { 
#        ew=EWrapper.new(@ib,self); 
#        ew.run
##        ew.report
#      }
      #debug "EWrapper thread started"
      
      show_stopper = Proc.new {
        #debug "show stopper *************************************"
        connection.close { EventMachine.stop }
      }
      
      puts "watch_for_new_orders(channel)"
      watch_for_new_orders(channel)
      watch_for_md_requests(channel) if mkt_data_server
      watch_for_md_unrequests(channel) if mkt_data_server
      #watch_for_account_requests(channel)
      
      alert "query account data"
      query_account_data
      
      clear

      Signal.trap("INT") { puts "interrupted caught in MyIb"; connection.close { EventMachine.stop } }
#      t2.join
    end
    
    
    t1.join
  end
end
