require 'singleton'
require "stringio"
require "account_mgr"
require "alert_mgr"
require "order_struct"
require "s_n"
require "log_helper"

class InvalidOrderError < StandardError; end

class Trader
  include Singleton
  include LogHelper

  attr_reader :sequencer, :account_mgr

  def initialize
    @accounts    = {}
    @account_mgr = AccountMgr.new
    @alert_mgr = AlertMgr.new
    @sequencer   = SN.instance
  end
  
  def new_order(trade)
    #puts "new_order(#{trade.inspect})"
    #puts "new_order(#{trade.attributes})"
    account = (@accounts[trade.account_name] ||= 
               account_mgr.get_account(trade.account_name))
               #AccountProxy.new(account_name: trade.account_name))
    escrow = (trade.mm_size.to_i * trade.limit_price.to_f).round(2)
# smz - not an exceptional condition
    raise "Funds not available" unless
      (account.funds_moved_to_escrow?(escrow))
    trade.escrow = escrow

    order = OrderStruct.from_hash(trade.attributes)
    # meta data
    order.order_id = sequencer.next_order_id
    order.pos_id = trade.pos_id
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

    order.add_note("New order, #{order.action} #{order.order_qty} " +
                   "#{order.ticker} @#{order.limit_price}")
    order.notes = (order.notes||"") +
                   "New order, #{order.action} #{order.order_qty} " +
                   "#{order.ticker} @#{order.limit_price};"
    order.order_status = "submit"

    trans = StringIO.new
    raise InvalidOrderError, trans.string unless valid_order?(order, trans)
    order
  rescue => e
    raise InvalidOrderError, "exception in creating new_order: #{e.message}"
  end

  def unwind_order(position)
    raise InvalidOrderError, "position not open" unless (position.status == 'open')
    debug "Trader: position open, creating unwind order"
    order = OrderStruct.from_hash(  pos_id:       position.pos_id, 
                                    order_id:     sequencer.next_order_id,
                                    sec_id:       position.sec_id, 
                                    ticker:       position.ticker,
                                    mkt:          position.mkt, 
                                    action:       position.stop_action, 
                                    action2:      :to_close,
                                    order_qty:    Integer(position.quantity.abs), 
                                    price_type:   'MKT', 
                                    limit_price:  0, 
                                    broker:       position.broker        )    
    trans = StringIO.new
    raise InvalidOrderError, trans.string unless valid_order?(order, trans)
    debug "Trader: position open, unwind order valid"
    order
  end

  def create_target_exit(pos_id,sec_id,side,price)
    alert_id = (side == "long") ? market_above_alert(pos_id, sec_id, price)
                                : market_below_alert(pos_id, sec_id, price)
    @alert_mgr.purge_alerts(self.class, sec_id, pos_id, alert_id)
  end

  def triggered_exits(bar,do_not_exit_flag)
    debug "Trader#triggered_exits(#{bar})"
    exits = @alert_mgr.triggered(self.class, bar.sec_id, bar.high, bar.low, do_not_exit_flag)
    show_info "Trader#triggered_exits: exits=#{exits}"
    exits.each_with_object([]) do |pos_id, arr|
      do_not_exit_flag ? (warn "Do Not Exit set for #{bar.sec_id}") : (show_info "Trader: create unwind order for pos #{pos_id}")
      next if do_not_exit_flag
      #order = unwind_order(pos)
      #show_info "Trader: unwind order is #{(order.valid?) ? "valid" : "invalide"}"
      #arr << order if order.valid?
      arr << pos_id
    end
  end

  ##################
  private
  ##################

  def market_above_alert(ref_id, sec_id, level, one_shot=true)
    #puts "market_above_alert(#{ref_id}, #{sec_id}, #{level}, #{one_shot})"
    @alert_mgr.add_alert(self.class, ref_id,  { sec_id: sec_id,
                                                op:       :>=,
                                                level:  level,
                                                one_shot: true } )
  end

  def market_below_alert(ref_id, sec_id, level, one_shot=true)
    #puts "market_below_alert(#{ref_id}, #{sec_id}, #{level}, #{one_shot})"
    alert_id = @alert_mgr.add_alert(self.class, ref_id,  { sec_id: sec_id,
                                                op:       :<=,
                                                level:  level,
                                                one_shot: true } )
    debug "RiskMgr#market_below_alert: alert_id = #{alert_id}"
    alert_id
  end

  def valid_order?(order, transcript=StringIO.new)
    rtn = true
    unless order.order_qty > 0
      transcript.puts "order:#{order.order_id} bad order qty:#{order.order_qty}"
      rtn = false
    end
    unless %w(buy sell).include?(order.action.to_s)
      transcript.puts "order:#{order.order_id} bad action:#{order.action.to_s}/#{order.action.class}"
      rtn = false
    end
    unless (order.ticker =~ /\w+/)
      transcript.puts "order:#{order.order_id} bad ticker:#{order.ticker}"
      rtn = false
    end
    unless (order.price_type == "MKT" || 
            ( order.price_type == "LMT" && order.limit_price.is_a?(Numeric) ))
      transcript.puts "order:#{order.order_id} bad pricing:#{order.price_type}/#{order.limit_price}"
      rtn = false
    end
    rtn
  rescue
    warn "invalid order!, order:#{order.inspect}"
    transcript.puts "invalid order!, order:#{order.inspect}"
    false
  end
end


