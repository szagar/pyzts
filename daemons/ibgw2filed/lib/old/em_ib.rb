#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require 'screen'
require 'order_struct'
require 's_m'
#require "e_wrapper_bunny"
require "zts_config"
require "ib-ruby"
require "amqp"
require "json"
require 'adminable'
#require 'zts_logger'
#require 'simple_logger'
require 'configuration'
require 'launchd_helper'
require 'zts_ib_constants'
require 'fill'

#Screen.clear

class EmIb
  include LaunchdHelper
  include Adminable
#  include SimpleLogger
  attr_accessor :a, :account_code, :this_broker
  attr_accessor :exchange
  attr_accessor :proc_name, :redis
  
  attr_reader :ib, :mkt_data_server, :ticker_plant
  attr_reader :sock_host, :sock_port

  AccountAlias = { 'DU95153' => 'ib_paper' }

  def initialize(broker, opts={})
    config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      broker})

    lstdout "config: #{config.inspect}"
    lstdout "config.broker_code: #{config.broker_code}"
    lstdout "config.host:        #{config.host}"
    lstdout "config.gw_port:     #{config.gw_port}"
    lstdout "config.tws_port:    #{config.tws_port}"
    lstdout "config.sock_port:    #{config.sock_port}"
    lstdout "config.sock_host:    #{config.sock_host}"
    lstdout "config.client_id:   #{config.client_id}"
    lstdout "config.md_status:   =#{config.md_status}="
    lstdout "config.md_id:       #{config.md_id}"
    lstdout "broker: #{broker}  md_status: #{config.md_status}"

    #@mkt_data_server = (config.md_status.eql?("on")) ? true : false
    @ticker_plant = config.md_id
    @mkt_data_server = config.md_status
    lstdout "mkt_data_server = #{mkt_data_server}"

    ib_app = opts[:ib_app] ||= "gw"
    port   = config.send("#{ib_app}_port")
    @ib = IB::Connection.new(:host      => config.host,
                             :client_id => config.client_id, 
                             :port      => port)
                             
    @ib.wait_for :NextValidId
                         
    @contracts = Hash.new
    progname = File.basename(__FILE__,".rb") 
    @proc_name = "#{progname}-#{broker}"
    
    @sock_host = config.sock_host
    @sock_port = config.sock_port

    lstdout "config.sock_host:    #{config.sock_host}"
    @this_broker = broker
    
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    
    puts "progname=#{progname}"
    #simpleLoggerSetup(proc_name)
    
    lstdout set_hdr("IB Gateway, program name : #{progname}")
    lstdout set_hdr("            proc name    : #{proc_name}")
    lstdout set_hdr("            broker       : #{this_broker}")
  end
  
  def clear
    write_hdr
  end
  
  def alert(str)
    #talk str
    lstderr str
  end
  
  def place_order(ib_order, contract)
    lstderr "place_order: #{ib_order}"
    lstderr "place_order: #{contract}"
    @ib.wait_for :NextValidId
    attr = ib_order.attributes
    lstdout "Place Order(pos_id:#{attr['order_ref']}):  #{attr['side']} #{attr['quantity']} "\
                "#{contract.attributes['symbol']}@#{attr['limit_price']} #{attr['order_type']} (#{attr['open_close']})"
    ib_order_id = @ib.place_order ib_order, contract
    lstdout "Order Placed (IB order number = #{ib_order_id})"
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
      #lstderr "data = SM.send(#{mkt}_indics,#{sec_id})"
      data = SM.send("#{mkt}_indics",sec_id)
      #lstderr "mkt=#{mkt}"
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
      redis.hset "md:status:#{ticker_id}", "ticker_plant", ticker_plant
    end
  end
  
  def bar5s_active(ticker_id)
    (redis.hget("md:status:#{ticker_id}", "status")  == "bar5s")
  end

  def req_md( ticker_id, contract )
    lstderr "req_md(#{ticker_id}, #{contract.inspect})"
    lstdout "Market Data Request: ticker_id=#{ticker_id}"
    
    @ib.send_message :RequestRealTimeBars, :ticker_id => ticker_id, :contract => contract, 
             :data_type => "TRADES", :bar_size => "5 secs"
    set_md_status(ticker_id,"bar5s")
  end
  
  def unreq_md( ticker_id )
    if (ZtsApp::Config::IB[this_broker.to_sym][:mktdta][:id] == redis.hget("md:status:#{ticker_id}", "ticker_plant")) then
      lstderr "unreq_md(#{ticker_id})"
      lstdout "Market Data UnRequest: ticker_id=#{ticker_id}"
    
      @ib.send_message :CancelRealTimeBars, :id => ticker_id
      set_md_status(ticker_id,"InActive")
    else
      $stderr.puts "Could not Cancel MktData for #{ticker_id} on #{ZtsApp::Config::IB[this_broker.to_sym][:mktdta][:id]}"
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
    
    lstdout set_hdr("->(#{exchange.name}/#{routing_key})")
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      to_broker = headers.message_id
      lstdout "to_broker = #{to_broker}"
      lstdout "this_broker = #{this_broker}"
      lstdout "IB conn: #{ZtsApp::Config::IB[this_broker.to_sym].inspect}"
      if ( to_broker == this_broker ) then
        order_hash = JSON.parse(payload)
        $stderr.puts "order_hash=#{order_hash}"
        order = OrderStruct.from_hash(order_hash)
        $stderr.puts "em_ib: order attributes: #{order.attributes}"
        $stderr.puts "contract = get_contract( #{order.mkt}, #{order.sec_id} )"
        contract = get_contract( order.mkt, order.sec_id )
        action = order.action.upcase

        puts "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
                              "limit_price: #{order.limit_price || 0}," \
                              "action:"" #{action}," \
                              "order_type => #{order.price_type}," \
                              "order_ref: #{order.pos_id}"
        
        lstdout "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
                              "limit_price: #{order.limit_price || 0}," \
                              "action:"" #{action}," \
                              "order_type => #{order.price_type}," \
                              "order_ref: #{order.pos_id}"
        ib_order = IB::Order.new :total_quantity => order.order_qty.to_i,
                              :limit_price => order.limit_price || 0,
                              :action => action,
                              :order_type => order.price_type,
                              :order_ref => order.pos_id
        #lstdout ib_order
        puts ib_order
              
        place_order ib_order, contract
      end
    end
  end
  
  def watch_for_md_requests(channel)
    lstdout "watch_for_md_requests Entered --------------"
    queue_name = ZtsApp::Config::ROUTE_KEY[:request][:bar5s]
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:bar5s]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                             ZtsApp::Config::EXCHANGE[:market][:options])
    lstdout set_hdr("->(#{exchange.name}/#{routing_key})")
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      lstderr "mktdta monitor req: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
      rec = JSON.parse(payload)
      lstderr "rec=#{rec.inspect}(#{rec.class})"
      sec_id = rec["sec_id"]
      mkt    = rec['mkt']
      force = rec['force'] || false
      contract = get_contract( mkt, sec_id )
      lstderr "contract: #{contract.inspect}"
      lstdout "market data request: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
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
  
  def watch_for_account_requests(channel)
    queue_name = routing_key = ZtsApp::Config::ROUTE_KEY[:request][:acctData]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                             ZtsApp::Config::EXCHANGE[:market][:options])
    lstdout set_hdr("->(#{exchange.name}/#{routing_key})")
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      puts "query_account_data"
      query_account_data
    end
  end
  
  def run   ############### new
    t1 = Thread.new { EM.run }
    EM.next_tick do
      puts "start EM"

      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
      channel = AMQP::Channel.new(connection)

      #EM::start_server "0.0.0.0", 4050, AmqpRelay, channel
      #puts "running AMQP relay on 4050"

#      Fiber.new do
#        bar_data = EmMarketData.new(@ib)
#        bar_data.subscribe
#      end.resume

#      Fiber.new do
#        info_stuff = EmIbInfo.new(@ib)
#        info_stuff.subscribe
#      end.resume
      t2 = Thread.new {EmIbInfo.new(@ib, sock_host, sock_port).subscribe}
      t3 = Thread.new {EmMarketData.new(@ib, sock_host, sock_port).subscribe}
      t4 = Thread.new {EmTrades.new(@ib, this_broker, sock_host, sock_port).subscribe}

      watch_admin_messages(channel)
      ignore_admin_all

      watch_for_new_orders(channel)
      watch_for_md_requests(channel) if mkt_data_server
      puts "watch_for_md_requests(channel)" if mkt_data_server
      watch_for_account_requests(channel)

      Signal.trap("INT") { puts "interrupted caught in EmIb";
                           connection.close { EventMachine.stop } }

#      trade_stuff = EmTrades.new(@ib, channel)
#      trade_stuff.callback {puts "trade_stuff callback"}
#      Thread.new {trade_stuff.subscribe}    #; EM.stop}

#      info_stuff = EmIbInfo.new(@ib, channel)
#      info_stuff.callback {puts "info_stuff callback"}
#      Thread.new {info_stuff.subscribe}    #; EM.stop}

      query_account_data

      #write_hdr
      t2.join
      t3.join
      t4.join
    end
    t1.join
  end ############### new
end

require 'socket'      # Sockets are in standard library
class EmMarketData
  include EM::Deferrable
  include LaunchdHelper
  attr_reader :ib, :s

  def initialize(ib, host, port)
    @ib = ib
    @s = TCPSocket.open(host, port)
  end

  def md_routing_key(std_route,ticker_id)
    market,id = SM.decode_ticker(ticker_id)    # IB::SECURITY_TYPES
    "#{std_route}.#{market}.#{id}"
  end

  def subscribe
    # bar data
    puts "ib.subscribe(:RealTimeBar) do |msg|"
    ib.subscribe(:RealTimeBar) do |msg|
      #tick_types[msg.data[:tick_type]] =+ 1
      print "."
      puts "bar data : ==#{msg.data[:bar].inspect}=="

      msg_code = "005"
      payload = {msg_code: msg_code, payload: {request_id: msg.data[:request_id],
                                                      bar: msg.data[:bar]}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    # tick data
    ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) do |msg|
      msg.data[:tick_type_str] = IB::TICK_TYPES[msg.data[:tick_type]]
      print "-"

      msg_code = "006"
      payload = {msg_code: msg_code, payload: {msg: msg.data}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    # misc data
    ib.subscribe(:TickOptionComputation, :TickEFP) do |msg|
      print "?"
    end

  end
end

class EmTrades
  include EM::Deferrable
  include LaunchdHelper
  attr_reader :ib, :exchange, :flow_exchange, :this_broker

  def initialize(ib, this_broker, host, port)
    @ib = ib
    @this_broker = this_broker
    @s = TCPSocket.open(host, port)
  end

  def subscribe
    # commission data
    ib.subscribe(:CommissionReport) do |msg|
      msg_code = "007"
      payload = {msg_code: msg_code, payload: {msg: msg.data}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    # execution data
    @ib.subscribe(:ExecutionData) do |msg|
      exec = msg.data[:execution]
      con  = msg.data[:contract]
      lstdout "ExecutionData.execution: #{exec.inspect}"
      lstdout "ExecutionData.contract: #{con.inspect}"
      pos_id = exec[:order_ref] || -1

      lstdout "ExecutionData tkr:#{con[:symbol]} pos_id:#{exec[:order_ref]} exch:#{exec[:exchange]} side:#{exec[:side]} qyt:#{exec[:quantity]} px:#{exec[:price]} cumqty:#{exec[:cumulative_quantity]} avgpx:#{exec[:average_price]}"

      action = ZTS::IB.action(exec[:side])
      fill = Fill.new(ref_id: '11111', pos_id: pos_id, sec_id: SM.sec_lookup(con[:symbol]),
                      exec_id: exec[:exec_id],
                      price: exec[:price], avg_price: exec[:average_price],
                      qty: exec[:quantity], action: action,
                      broker: this_broker, account: exec[:account_name])

      msg_code = "008"
      payload = {msg_code: msg_code, payload: {fill: Marshal.dump(fill)}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload
    end

    # order status
    @ib.subscribe(:OrderStatus) do |msg|
      order_state = msg.order_state
      data        = msg.data
      ord         = data[:order]
      con         = data[:contract]
      state       = data[:order_state]

      order_update = {  perm_id: state[:perm_id], status: state[:status], filled_qty: state[:filled],
                        leaves: state[:remaining], avg_price: state[:average_fill_price],
                        parent_id: state[:parent_id] }

      #routing_key = ZtsApp::Config::ROUTE_KEY[:order_flow][:order_state]
      #lstdout "<-(#{db_exchange.name}/#{routing_key}): order_update.to_json"
      #lstderr "<-(#{db_exchange.name}/#{routing_key}): #{order_update.inspect}.to_json"
      #db_exchange.publish(order_update.to_json, :routing_key => routing_key, :persistent => true)
 
      msg_code = "009"
      payload = {msg_code: msg_code, payload: {order_status: order_update}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    # open order
    @ib.subscribe(:OpenOrder) do |msg|
      data  = msg.data
      ord   = data[:order]
      con   = data[:contract]
      state = data[:order_state]

      lstdout "OpenOrder: #{con[:symbol]} pos_id:#{ord[:order_ref]} status:#{state[:status]} #{ord[:action]} #{ord[:total_quantity]}/#{state[:filled]} @#{ord[:limit_price]} opncls:#{ord[:open_close]} client_id:#{ord[:client_id]}"
      lstderr "OpenOrder.order: #{ord.inspect}"
      lstderr "OpenOrder.contract: #{con.inspect}"
      lstderr "OpenOrder.order_state: #{state.inspect}"

      order = OrderStruct.from_hash(  account:    ord[:account],
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
                          broker:      this_broker,      
                          broker_ref:  ord[:local_id], 
                          notes:       state[:warning_text])

      msg_code = "010"
      payload = {msg_code: msg_code, payload: {order: order.attributes}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end
  end
end

class EmIbInfo
#  include EM::Deferrable
  include LaunchdHelper

  attr_reader :ib   #, :exchange, :db_exchange
  attr_reader :s

  def initialize(ib,host,port) #, channel)
    puts "EmIbInfo#initialize(ib/#{ib.class})"
    @ib = ib
    @s = TCPSocket.open(host, port)
    @cnt = 0
  end
  def subscribe
    puts "#{ib.class}.subscribe(:Alert) do |msg|"
    ib.subscribe(:Alert) do |msg|
      msg_code = "001"
      payload = {msg_code: msg_code, payload: {msg: msg.to_human}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    ib.subscribe(:AccountValue) do |msg|
      next unless msg.data[:version] == 2
      #if (msg.data[:key].eql? 'AccountCode')
        #m.account_code = msg.data[:value]
        #if ( m.account_code != ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code] ) then
        #  m.alert "wrong account code #{msg.data[:value]} (#{ZtsApp::Config::IB[m.this_broker.to_sym][:broker_code]})"
        #end
      #end
      key = msg.data[:key].tr("-","_")
#      routing_key = ZtsApp::Config::ROUTE_KEY[:data][:account][:balance]
#      lstdout "<- AccountValue: #{msg.data[:account_name]} #{key} => #{msg.data[:value]}"
      @cnt += 1

      msg_code = "002"
      payload = {msg_code: msg_code, payload: {account: msg.data[:account_name],
                                                   key: key,
                                                 value: msg.data[:value]
                                              }}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    ib.subscribe(:PortfolioValue) do |msg|
      data = msg.data
      contract = data[:contract]
      msg_code = "011"
      payload = {msg_code: msg_code, payload: { :ticker => contract[:symbol],
                                                :position => data[:position],
                                                :market_price => data[:market_price],
                                                :market_value => data[:market_value],
                                                :average_price => data[:average_cost],
                                                :unrealized_pnl => data[:unrealized_pnl],
                                                :realized_pnl => data[:realized_pnl],
                                                :broker_account => data[:account_name]
                                              } }

      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end

    # account download end
    ib.subscribe(:AccountDownloadEnd) do |msg|
      msg_code = "003"
      payload = {msg_code: msg_code, payload: {msg: msg.data}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json
    end 
 
    # account update time end
    ib.subscribe(:AccountUpdateTime) do |msg|
      msg_code = "004"
      payload = {msg_code: msg_code, payload: {msg: msg.data}}
      lstdout "(#{msg_code}): #{payload[:payload]}"
      @s.puts payload.to_json 
    end 
  end
end

module AmqpRelay
  attr_reader :channel

  def initialize(channel)
    @channel = channel
    @cnt = 0
  end

  def post_init
    puts "-- someone connected to the AMQP relay server:"
  end

  def receive_data data
#    begin
       @cnt += 1
puts "(#{@cnt}):*"
#      rec = JSON.parse(data)
#      case rec['msg_code']
#      when "001"
#        puts "============ AccountValue: #{rec}"
#      else
#        puts "============ Message Code:#{rec['msg_code']} Not recognized"
#      end
#      #puts "-- received: >>>>>>#{rec}<<<<<<<<<"
#    end
#  rescue
  end
end

