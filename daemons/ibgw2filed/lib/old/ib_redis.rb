#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require 'e_wrapper_redis'
require 'order_struct'
require "s_m"
require "zts_config"
require "ib-ruby"
require "json"
require 'configuration'

class IbRedis
  attr_reader :this_broker, :this_tkr_plant, :redis, :hdr
  attr_reader :channel_new_order, :channel_unreq_bars
  attr_reader :channel_req_bars, :channel_req_account_data

  def initialize(broker, opts={})
    @this_broker = broker
    config = opts[:config] ||=
             Configuration.new({filename: 'ib.yml',
                                env:      this_broker})

    redis_channels = Configuration.new({filename: 'redis_channels.yml',
                                        env:      'development'})

    puts "md_status = #{config.md_status}"
    @mkt_data_server = config.md_status
    puts "@this_tkr_plant = #{config.md_id}"
    @this_tkr_plant = config.md_id

    @channel_new_order        = redis_channels.new_order
    @channel_unreq_bars       = redis_channels.unreq_bars
    @channel_req_bars         = redis_channels.req_bars
    @channel_req_account_data = redis_channels.req_account_data

    ib_app = opts[:ib_app] ||= "gw"
    port   = config.send("#{ib_app}_port")
    puts "@ib = IB::Connection.new :host      => #{config.host}, \
                                   :client_id => #{config.client_id}, \
                                   :port      => #{port}"
    @ib = IB::Connection.new(:host      => config.host,
                             :client_id => config.client_id, 
                             :port      => port)
                             
    puts "@ib=#{@ib}"
    @ib.wait_for :NextValidId
                         
    @contracts = Hash.new
    progname = File.basename(__FILE__,".rb") 
    proc_name = "ib_gateway-#{this_broker}"
    
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    
    puts "progname=#{progname}"

    @hdr = []    
    set_hdr "IB Gateway, program name : #{progname}"
    set_hdr "            IB app       : #{ib_app}"
    set_hdr "            proc name    : #{proc_name}"    
    set_hdr "            broker       : #{this_broker}"    
  end
  
  def debug str
    puts str
  end
  def info str
    puts str
  end

  def set_hdr(str)
    @hdr << str
    str
  end

  def write_hdr
    puts "====================="
    hdr.map { |m| puts m }
    puts "====================="
  end

  def clear
    write_hdr
  end
  
  def alert(str)
    warn str
  end
  
  def place_order(ib_order, contract)
    debug "place_order: #{ib_order}"
    debug "place_order: #{contract}"
    @ib.wait_for :NextValidId
    attr = ib_order.attributes
    info "Place Order(pos_id:#{attr['order_ref']}): #{attr['side']} #{attr['quantity']} "\
                "#{contract.attributes['symbol']}@#{attr['limit_price']} "\
                "#{attr['order_type']} (#{attr['open_close']})"
    ib_order_id = @ib.place_order ib_order, contract
    info "Order Placed (IB order number = #{ib_order_id})"
    #ib.send_message :RequestAllOpenOrders
  end

  def get_ticker_id(mkt, sec_id)
    SM.encode_ticker(mkt, sec_id)
  end
  def get_contract( data )
    #tkr_id = get_ticker_id(mkt, sec_id)
    tkr_id = data['sec_id'].to_i + 100000
    if @contracts.member?(tkr_id) then
      return @contracts[tkr_id]
    else
      #data = SM.send("#{mkt}_indics",sec_id)
      sec_exchange = 'SMART'
      #sec_exchange = data['exchange'] if (mkt == :index)
      @contracts[tkr_id] = IB::Contract.new(:symbol => data['ib_tkr'],
                                           :currency => "USD",
                                           :sec_type => 'STK',  #mkt,
                                           :exchange => sec_exchange,
                                           :description => data['desc'])
    end
  end
  
  def set_md_status(ticker_id,status)
    if status == "InActive"
      redis.del "md:status:#{ticker_id}"
    else
      redis.hset "md:status:#{ticker_id}", "status", status
      redis.hset "md:status:#{ticker_id}", "ticker_plant",
                 ZtsApp::Config::IB[this_broker.to_sym][:mktdta][:id]
    end
  end
  
  def bar5s_active(ticker_id)
    (redis.hget("md:status:#{ticker_id}", "status")  == "bar5s")
  end

  def req_md( req )
    sec_id   = req["sec_id"]
    mkt      = req['mkt']
    force    = req['force'] || false
 data = { 'sec_id' => sec_id, 'ib_tkr' => req['ib_tkr'], 'desc' => "" } 
    contract = get_contract(data)
    debug "contract: #{contract.inspect}"
    info "market data request: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
    #tkr_id = get_ticker_id( mkt, sec_id ) rescue return
    tkr_id = sec_id.to_i + 100000

    debug "req_md(#{tkr_id}, #{contract.inspect})"
      info "Market Data Request: ticker_id=#{tkr_id}"
    
    @ib.send_message :RequestRealTimeBars, :ticker_id => tkr_id,
                                           :contract => contract, 
                                           :data_type => "TRADES",
                                           :bar_size => "5 secs"
    #set_md_status(tkr_id,"bar5s")
  end
  
  def unreq_md( ticker_id )
    tkr_plant = redis.hget("md:status:#{ticker_id}", "ticker_plant")
    if (this_tkr_plant == tkr_plant) then
      debug "unreq_md(#{ticker_id})"
      info "Market Data UnRequest: ticker_id=#{ticker_id}"
    
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
  
  def listen
    channels = [ channel_new_order, channel_unreq_bars,
                 channel_req_bars,  channel_req_account_data ]
    redis.subscribe(channels) do |on|
      on.message do |channel, msg|
        puts "#{channel}/#{msg}"
        case channel
        when channel_new_order
          order_hash = JSON.parse(msg)
          puts "##{channel} - [#{order_hash}]"
        when channel_unreq_bars
          puts "##{channel} - [#{msg}]"
        when channel_req_bars
          puts "##{channel} - [#{msg}]"
          req = JSON.parse(msg)
          req_md(req)
        when channel_req_account_data
          puts "##{channel} - [#{msg}]"
        end
      end
    end
  end

  def watch_for_new_orders
    redis.subscribe channel_new_order do |on|
      on.message do |channel, msg|
        order_hash = JSON.parse(msg)
        puts "##{channel} - [#{order_hash}]"
    
        to_broker = order_hash['broker']
        info "to_broker = #{to_broker}"
        info "this_broker = #{this_broker}"
        info "IB conn: #{ZtsApp::Config::IB[this_broker.to_sym].inspect}"
        if ( to_broker == this_broker ) then
          info "order_hash=#{order_hash}"
          order = OrderStruct.from_hash(order_hash)
          info "my_ib: order attributes: #{order.attributes}"
          info "contract = get_contract( #{order.mkt}, #{order.sec_id} )"
          contract = get_contract( order.mkt, order.sec_id )
          action = order.action.upcase

          info "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
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
          info ib_order
              
          place_order ib_order, contract
        end
      end
    end
  end
  
  def watch_for_md_unrequests
    set_hdr "subscribe ->(#{channel_unreq_bars})"
    redis.subscribe channel_unreq_bars do |on|
      on.message do |channel, msg|
        req = JSON.parse(msg)
        puts "##{channel} - [#{req}]"
    
        sec_id = req["sec_id"]
        mkt    = req['mkt']
        force  = req['force'] || false
        contract = get_contract( mkt, sec_id )
        debug "contract: #{contract.inspect}"
        info "market data unrequest: #{contract.attributes['symbol']}(#{sec_id})  mkt(#{mkt})  force(#{force})"
        tkr_id = get_ticker_id( mkt, sec_id ) rescue return
        unreq_md(tkr_id)
      end
    end
  end

  def watch_for_md_requests
    set_hdr "subscribe ->(#{channel_req_bars})"
    redis.subscribe channel_req_bars do |on|
      on.message do |channel, msg|
        req = JSON.parse(msg)
        puts "##{channel} - [#{req}]"
    
        sec_id   = req["sec_id"]
        mkt      = req['mkt']
        force    = req['force'] || false
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
  end
  
  def watch_for_account_requests
    set_hdr "subscribe ->(#{channel_req_account_data})"
    redis.subscribe channel_req_account_data do |on|
      on.message do |channel, msg|
        req = JSON.parse(msg)
        puts "##{channel} - [#{req}]"
        query_account_data
      end
    end
  end
  
  def run
    Fiber.new {
      ew=EWrapper.new(@ib)
      ew.run
    }.resume
      
puts "1"
req_md( {'ib_tkr' => 'STSI', 'sec_id' => '4162', 'mkt' => :stock, 'force' => true} )
    listen
puts "2"
#    watch_for_md_requests       if mkt_data_server
puts "3"
#    watch_for_md_unrequests     if mkt_data_server
puts "4"
#    watch_for_account_requests

    write_hdr
      
    alert "query account data"
    query_account_data
      

    Signal.trap("INT") { puts "interrupted caught in MyIb"; connection.close { EventMachine.stop } }
  end
end
