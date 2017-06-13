#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require 'order_struct'
require "s_m"
require "e_wrapper_bunny2"
require "zts_config"
require "ib-ruby"
require "amqp"
require "json"
require 'zts_logger'

class MyIb

  attr_accessor :a, :ib, :account_code, :progname, :this_broker
  attr_accessor :exchange
  attr_accessor :logger, :proc_name, :redis
  
  AccountAlias = { 'DU95153' => 'ib_paper' }

  def initialize(broker)
    @contracts = Hash.new
    @progname = File.basename(__FILE__,".rb") 
    @proc_name = "ib_gateway-#{broker}"
    
    @this_broker = broker
    
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    
    puts "progname=#{progname}"
    @logger = ZtsLogger.instance
    logger.set_proc_name(proc_name)
    
    #set_hdr "IB Gateway, program name : #{progname}"
    #set_hdr "            proc name    : #{proc_name}"    
    #set_hdr "            broker       : #{this_broker}"    
  end
  
  def clear
    #write_hdr
  end
  
  def alert(str)
    logger.talk str
    logger.warn str
  end
  
  def place_order(ib_order, contract)
    logger.debug "place_order: #{ib_order}"
    logger.debug "place_order: #{contract}"
    @ib.wait_for :NextValidId
    attr = ib_order.attributes
    logger.info "Place Order(pos_id:#{attr['order_ref']}):  #{attr['side']} #{attr['quantity']} "\
                "#{contract.attributes['symbol']}@#{attr['limit_price']} #{attr['order_type']} (#{attr['open_close']})"
    ib_order_id = @ib.place_order ib_order, contract
    logger.info "Order Placed (IB order number = #{ib_order_id})"
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
      #logger.debug "data = SM.send(#{mkt}_indics,#{sec_id})"
      data = SM.send("#{mkt}_indics",sec_id)
      #logger.debug "mkt=#{mkt}"
      sec_exchange = 'SMART'
      sec_exchange = data['exchange'] if (mkt == :index)
      @contracts[tkr_id] = IB::Contract.new(:symbol => data['ib_tkr'],
                                           :currency => "USD",
                                           :sec_type => 'STK',  #mkt,
                                           :exchange => sec_exchange,
                                           :description => data['desc'])
    end
  end
  
  def set_md_status(ticker,status)
    redis.hset "md:status:#{ticker}", "status", status
    redis.hset "md:status:#{ticker}", "ticker_plant", ZtsApp::Config::IB[this_broker.to_sym][:mktdta][:id]
  end
  
  def bar5s_active(ticker)
    status = redis.hget "md:status:#{ticker}", "status"
    (status == "bar5s") ? true : false
  end

  def req_md( ticker_id, contract )
    logger.debug "req_md(#{ticker_id}, #{contract.inspect})"
    logger.info "Market Data Request: ticker_id=#{ticker_id}"
    
    @ib.send_message :RequestRealTimeBars, :ticker_id => ticker_id, :contract => contract, 
             :data_type => "TRADES", :bar_size => "5 secs"
    set_md_status(ticker_id,"bar5s")
  end
  
  def unreq_md( ticker_id )
    if (ZtsApp::Config::IB[this_broker.to_sym][:mktdta][:id] == redis.hget("md:status:#{ticker_id}", "ticker_plant")) then
      logger.debug "unreq_md(#{ticker_id}, #{contract.inspect})"
      logger.info "Market Data UnRequest: ticker_id=#{ticker_id}"
    
      @ib.send_message :CancelRealTimeBars, :id => ticker_id
      set_md_status(ticker_id,"InActive")
    else
      $stderr.puts "Could not CancelRealTimeBars for #{ticker_id} on #{ZtsApp::Config::IB[this_broker.to_sym][:mktdta][:id]}"
    end
  end
  

  def query_account_data
    ib.send_message :RequestAccountData
    #ib.wait_for :AccountDownloadEnd
  end
  
  def watch_for_new_orders(channel)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:order_flow][:order]}.#{this_broker}"
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:order_flow][:name],
                             ZtsApp::Config::EXCHANGE[:core][:options])
    
    #set_hdr "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      to_broker = headers.message_id
      logger.info "to_broker = #{to_broker}"
      logger.info "this_broker = #{this_broker}"
      logger.info "IB conn: #{ZtsApp::Config::IB[this_broker.to_sym].inspect}"
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
        
        logger.info "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
                              "limit_price: #{order.limit_price || 0}," \
                              "action:"" #{action}," \
                              "order_type => #{order.price_type}," \
                              "order_ref: #{order.pos_id}"
        ib_order = IB::Order.new :total_quantity => order.order_qty.to_i,
                              :limit_price => order.limit_price || 0,
                              :action => action,
                              :order_type => order.price_type,
                              :order_ref => order.pos_id
        logger.info ib_order
        puts ib_order
              
        place_order ib_order, contract
      end
    end
  end
  
  def watch_for_md_requests(channel)
    queue_name = routing_key = ZtsApp::Config::ROUTE_KEY[:request][:bar5s]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                             ZtsApp::Config::EXCHANGE[:market][:options])
    #set_hdr "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      logger.debug "mktdta monitor req: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
      rec = JSON.parse(payload)
      logger.debug "rec=#{rec.inspect}(#{rec.class})"
      sec_id = rec["sec_id"]
      mkt    = rec['mkt']
      force = rec['force'] || false
      contract = get_contract( mkt, sec_id )
      logger.debug "contract: #{contract.inspect}"
      logger.info "market data request: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
      tkr_id = get_ticker_id( mkt, sec_id ) rescue return
      if ( rec['action'] == "on" ) then
        req_md(tkr_id, contract) if ((not bar5s_active(tkr_id)) || force)
      else
        unreq_md(tkr_id)
      end
    end
  end
  
  def watch_for_account_requests(channel)
    queue_name = routing_key = ZtsApp::Config::ROUTE_KEY[:request][:acctData]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                             ZtsApp::Config::EXCHANGE[:market][:options])
    #set_hdr "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      puts "query_account_data"
      query_account_data
    end
  end
  
  def run
    puts "@ib = IB::Connection.new :host => #{ZtsApp::Config::IB[this_broker.to_sym][:conn][:host]}," \
                              ":client_id => #{ZtsApp::Config::IB[this_broker.to_sym][:conn][:client_id]}," \
                             ":port => #{ZtsApp::Config::IB[this_broker.to_sym][:conn][:port]}"
    
    @ib = IB::Connection.new :host => ZtsApp::Config::IB[this_broker.to_sym][:conn][:host],
                             :client_id => ZtsApp::Config::IB[this_broker.to_sym][:conn][:client_id], 
                             :port => ZtsApp::Config::IB[this_broker.to_sym][:conn][:port]
                             
    @ib.wait_for :NextValidId
                         
    t1 = Thread.new { EventMachine.run }
    if defined?(JRUBY_VERSION)
     # on the JVM, event loop startup takes longer and .next_tick behavior
     # seem to be a bit different. Blocking current thread for a moment helps.
     sleep 0.5
    end

    puts "start EM"
    EventMachine.next_tick do
      #connection = AMQP.connect(connection_settings)
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
      
      channel = AMQP::Channel.new(connection)
    #  channel.prefetch(1)
      
      logger.amqp_config(channel)

      Fiber.new {
        ew=EWrapper.new(@ib,channel)
        ew.run
      }.resume
      # Subscribers
##      stop_t2 = false
#      t2 = Thread.new { 
#        ew=EWrapper.new(@ib,self); 
#        ew.run
##        ew.report
#      }
      #logger.debug "EWrapper thread started"
      
      show_stopper = Proc.new {
        #logger.debug "show stopper *************************************"
        connection.close { EventMachine.stop }
      }
      
      watch_for_new_orders(channel)
      watch_for_md_requests(channel)
      watch_for_account_requests(channel)
      
      alert "query account data"
      query_account_data
      
      clear

      Signal.trap("INT") { puts "interrupted caught in MyIb"; connection.close { EventMachine.stop } }
#      t2.join
    end
    
    
    t1.join
  end
end
