require 'singleton'
require "stringio"
require "order_struct"
require "s_n"

class InvalidOrderError < StandardError; end

class Trader
  include Singleton

  def initialize
    @accounts = {}
  end
  
  def new_order(trade)
    #puts "new_order(#{trade.attributes})"
    account = (@accounts[trade.account_name] ||= 
               AccountProxy.new(account_name: trade.account_name))
    #puts account.summary
    trade_value = trade.mm_size.to_i * trade.limit_price.to_f
    raise "Funds not available" unless
      (account.funds_moved_to_escrow?(trade_value))

    order = OrderStruct.from_hash(trade.attributes)
    # meta data
    order.order_id = SN.next_order_id
    order.ticker = trade.ticker
    order.account_name = trade.account_name

    # order data
    order.tif = "Day"
    order.price_type = "LMT"
    order.limit_price = trade.limit_price

    order.action  = (trade.side == "long") ? "buy" : "sell"
    order.action2 = "to_open"

    order.order_qty = trade.mm_size.to_f
    order.leaves = order.order_qty
    order.filled_qty = 0

    order.notes = (order.notes||"") +
                   "New order, #{order.action} #{order.order_qty} " +
                   "#{order.ticker} @#{order.limit_price};"
    order.order_status = "submit"

    raise InvalidOrderError unless order_is_valid?(order, $stdout)
    order
  rescue
  end

  def unwind_order(pos)
    order = OrderStruct.from_hash(JSON.parse(payload))
    stop_action = position.stop_action
    qty         = Integer(position.quantity.abs)
    broker      = position.broker
    ticker      = position.ticker
    status      = position.status
    sec_id      = position.sec_id
    mkt         = position.mkt
    
    return nil unless status.eql?('open')

    begin
      order = OrderStruct.from_hash(  pos_id:       pos_id, 
                                      sec_id:       sec_id, 
                                      ticker:       ticker,
                                      mkt:          mkt, 
                                      action:       stop_action, 
                                      action2:      :to_close,
                                      order_qty:    qty, 
                                      price_type:   'MKT', 
                                      limit_price:  0, 
                                      broker:       broker        )    
      logger.info "config_exit_order_from_pos_id: #{order}"
      order
    rescue
      alert "Could not create Exit Order !!"
      nil
    end
  end

  ##################
  private
  ##################

  def order_is_valid?(order, transcript=StringIO.new)
    rtn = true
    unless order.order_qty > 0
      transcript.puts "order:#{order.order_id} bad order qty:#{order.order_qty}"
      rtn = false
    end
    rtn
  end
end
__END__
  
  def exit_orders(channel)
    routing_key = ZtsApp::Config::ROUTE_KEY[:signal][:exit][:eod]
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload, symbolize_names: true)
      lstdout "->(#{exchange.name}/#{headers.routing_key}) #{rec}"
      
      pos_id = rec[:pos_id]

      lstdout "order = config_exit_order_from_pos_id(#{pos_id})"
      order = config_exit_order_from_pos_id(pos_id)
      if order == nil
        alert "#{__FILE__}(#{__LINE__}) Failed to create order for pos_id:#{pos_id}"
        next unless order
      end
      
      order.notes = (order.notes||"") + "EOD exit order, #{order.action} #{order.order_qty} #{order.ticker};"
      order.status = "new"

      lstdout order.notes
      track order.notes

      fire_order(order.broker, order)
    end
    
    routing_key = ZtsApp::Config::ROUTE_KEY[:signal][:exit][:stop]
    set_hdr "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      rec = JSON.parse(payload, symbolize_names: true)
      lstdout "->(#{exchange.name}/#{headers.routing_key}) #{rec}"
      
      pos_id = rec[:pos_id]
      
      lstdout "order = config_exit_order_from_pos_id(#{pos_id})"
      orde = config_exit_order_from_pos_id(pos_id)
      if order == nil
        alert "#{__FILE__}(#{__LINE__}) Failed to create order for pos_id:#{pos_id}"
        next unless order
      end
      
      order.notes = (order.notes||"") + "Stop order, #{order.action} #{order.order_qty} #{order.ticker};"
      order.order_status = "new"

      lstdout order.notes
      track order.notes

      fire_order(order.broker, order)
    end
  end
  
  def config(channel)
  end
  
  def run
    EventMachine.run do
#      timer = EventMachine::PeriodicTimer.new(20) do
#        $stderr.puts "#{proc_name}: the time is #{Time.now}"
#      end
      
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
      
      channel = AMQP::Channel.new(connection)
      
      @exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], 
                                ZtsApp::Config::EXCHANGE[:core][:options])
      @exch_order_flow = channel.topic(ZtsApp::Config::EXCHANGE[:order_flow][:name], 
                                       ZtsApp::Config::EXCHANGE[:market][:options])
      
      logger.amqp_config(channel)
      watch_admin_messages(channel)
      config(channel)
      
      logger.debug "watch for new orders"
      new_orders(channel)
      
      logger.debug "request exit orders for open positions"
      exit_orders(channel)
      
      clear
      Signal.trap("INT") { connection.close { EventMachine.stop } }
    end
  end
end

t = Trader.new
t.run
