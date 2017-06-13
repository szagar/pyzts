require 'singleton'
require 'portfolio_store'
require 'position_proxy'
require 'account_mgr'
require 'trader'
require "exit_mgr"
require "alert_mgr"
require "money_mgr"
#require "risk_mgr"
require "last_value_cache"
require "zts_constants"
require "date_time_helper"
require "misc_helper"
require "log_helper"

class InvalidTradeError < StandardError; end
class InvalidPositionError < StandardError; end

class PortfolioMgr
  include Singleton
  include ZtsConstants
  include LogHelper

  attr_accessor :risk_mgr

  def initialize
    @store       = PortfolioStore.instance
    @trader      = Trader.instance
    @lvc         = LastValueCache.instance
    @exit_mgr    = ExitMgr.instance
    @alert_mgr   = AlertMgr.new
    @money_mgr   = MoneyMgr.new
    #@risk_mgr    = RiskMgr.new
    #@mca         = MarketConditionAnalysis.instance
    @account_mgr = AccountMgr.new
    @accounts = {}
  end

  def create_manual_position(params)
    trans = StringIO.new
    unless valid_position?(params,trans)
      alert trans.string
      raise InvalidPositionError, "#{trans.string}, pos params: #{params}"
    end
    quantity = params.delete(:quantity)
    price    = params.delete(:price)
    escrow   = quantity * price #+ params[:fees]||0.0
    #20150214
    #pos_id = create_position(params)
    pos_id = new_position(params)
    initialize_position(params[:account_name], pos_id)
    update_position(params[:account_name], pos_id, quantity, escrow)
    buy(pos_id, quantity, price)
    #open_position(params[:account_name], pos_id)
    pos_id
  end

  def position_is_open?(pos_id)
    debug "position_is_open?: position(#{pos_id}).status = #{position(pos_id).status}"
    (PositionProxy.exists?(pos_id) && position(pos_id).status) == "open"
  end

  def position_is_timed?(pos_id)
    debug "position_is_timed?: position(#{pos_id}).trailing_stop_type = #{position(pos_id).trailing_stop_type}"
    (PositionProxy.exists?(pos_id) && position(pos_id).trailing_stop_type) == "timed"
  end

  def trade_order(trade)
    debug "PortfolioMgr#trade_order(#{trade.attributes})"
    trans = StringIO.new
    unless valid_trade?(trade,trans)
      raise InvalidTradeError, "#{trans.string.chomp}, trade_order: #{trade.attributes}"
    end
    #20150214
    #trade.pos_id = new_position(trade.attributes)
    if new_position?(trade.attributes) 
      trade.pos_id = new_position(trade.attributes)
      trade.add_note("New position(#{trade.pos_id})")
      debug "PortfolioMgr#trade_order: trade.pos_id = #{trade.pos_id}"
      initialize_position(trade.account_name, trade.pos_id)
    else
      trade.notes += ", " if trade.notes
      trade.notes += "Scale into position(#{trade.pos_id})"
    end
    debug "PortfolioMgr#trade_order pos_id = #{trade.pos_id}"
    @exit_mgr.create_timed_exit(trade.pos_id, trade.time_exit||1) if (trade.trailing_stop_type == "timed")
    order        = @trader.new_order(trade)
    update_position(trade.account_name, trade.pos_id, order.order_qty, trade.escrow)
    order
  rescue InvalidTradeError, InvalidTradeError, InvalidOrderError => e
    warn e.message
    NullOrder.new  
  end

  def check_for_exits(bar)
    debug "PortfolioMgr#check_for_exits(#{bar})"
    pos_ids = []
    orders = []
    #@risk_mgr.triggered_exits(bar,do_not_exit_flag?(bar.sec_id)).each do |order|
    @risk_mgr.triggered_exits(bar,false).each do |pid|
      show_action "Trailing Exit: pos_id=#{pid}"
      #status_change(order.pos_id, "pending")
      #status_change(pid, "pending")
      #orders << order
      pos_ids << pid
    end
    #@trader.triggered_exits(bar,false).each do |order|
    @trader.triggered_exits(bar,false).each do |pid|
      show_action "Target Exit: pos_id=#{pid}"
      #status_change(order.pos_id, "pending")
      #status_change(pid, "pending")
      #orders << order
      pos_ids << pid
    end
    debug "PortfolioMgr#check_for_exits: pos_ids=#{pos_ids}"
    pos_ids.each do |pid|
      debug "PortfolioMgr#check_for_exits: need exit for pos_id: #{pid}"
      o = unwind_order(pid)
      debug "PortfolioMgr#check_for_exits: unwind order: #{o}"
      if o.valid?
        orders << o
        status_change(pid, "pending")
      end
      orders
    end
    orders
  end

  def unwind_order(pos_id)
    debug "unwind_order(#{pos_id})"
    pos = position(pos_id)
    order = @trader.unwind_order(pos)
    debug "PortfMgr#unwind_order: order=#{order.to_human}"
    order
  rescue InvalidOrderError => e
    alert e.message
    warn e.message
    NullOrder.new  
  end

  def first_fill(pos)
    open_position(pos.account_name, pos.pos_id)
    set_scale_in_alerts(pos) if account(pos.account_name).pyramid_positions?
  end

  def buy(pos_id, qty, price, fees=0)
    action "PortfolioMgr#buy(pos_id:#{pos_id}, qty:#{qty}, price:#{price}, fees:#{fees})"
    pos = position(pos_id)
    first_fill(pos) unless pos.is_open?
    #open_position(pos.account_name, pos_id) if pos.side == "long"
    new_qty = pos.buy(qty, price)
    close_position(pos) if(new_qty == 0)
    total_cost   = price * qty + fees
    equity_value = price * qty

    action "PortfolioMgr#buy: transfer payment: total_cost: #{total_cost}, equity_value=#{equity_value})"
    account(pos.account_name).transfer_payment(total_cost,equity_value)
               # escrow            => pay for equity
               #   cash            => pay for equity
               #     debit_balance => pay for equity
#    remaining_escrow = (new_qty <= 0) ? pos.close_and_release_escrow : 0.0
               # position status = closed
               # closed_date     = today
               # remove_position_alerts
               # return any remaining escrow
               # set positions escrow = 0
#    account(pos.account_name).free_escrow(remaining_escrow)
               # debit_balance 
               #   then cash
               # escrow
    update_account(pos.account_name)
    return pos
  end

  def sell(pos_id, qty, price, fees=0)
    action "sell(pos_id:#{pos_id}, qty:#{qty}, price#{price})"
    pos = position(pos_id)
    open_position(pos.account_name, pos_id) if pos.side == "short"
    new_qty = pos.sell(qty, price)

    close_position(pos) if(new_qty == 0)

    total_cost   = price * qty + fees
    equity_value = price * qty

    account(pos.account_name).adj_for_proceeds(total_cost,equity_value)
    update_account(pos.account_name)
    return pos
  end

  def position(pos_id)
    #debug "PortfolioMgr#position(#{pos_id})"
    @store.get(pos_id)
  end

  def init_positions(account_name)
    @store.init_positions(account_name)
  end

  def open_positions(account_name)
    @store.open_positions(account_name)
  end

#  def open_positions_by_sid(sid)
#    @store.open_positions_by_sid(sid)
#  end

  def closed_positions(account_name)
    @store.closed_positions(account_name)
  end

  def sids_of_open_positions
    @store.sids_of_open_positions
  end

  def update_account(account_name)
    action "Update account: #{account_name}"
    #@store.update_account_for_position(account_name)
    acct = account(account_name)
    acct.long_locked_in = @store.calc_locked_in_longs(account_name)
    acct.long_market_value = long_market_value(account_name)
    acct.number_positions  = @store.calc_number_of_positions(account_name)
    #acct. = @store.calc_number_of_shares(account_name)
  end

  def long_market_value(account_name)
    @store.calc_long_market_value(account_name)
  end

  def cost_long_positions(account_name)
    @store.calc_cost_long_positions(account_name)
  end

  def release_excess_escrow(pos_id)
    action "Release excess escrow for position: #{pos_id}"
    pos = position(pos_id)
debug "PortfolioMgr#release_excess_escrow: pos = #{pos.dump}"
debug "PortfolioMgr#release_excess_escrow: pos.account_name = #{pos.account_name}"
    amount = pos.release_escrow
    account(pos.account_name).release_excess_escrow(amount)
  end

  def cancel_pending_positions(account_name)
    action "Cancel pending positions for account: #{account_name}"
    init_positions(account_name).each do |pos_id|
      p = position(pos_id)
      cancel_position(p)
    end
    @alert_mgr.cleanup("EntryEngine")
  end

  def mark_positions(account_name)
    action "Mark positions for account: #{account_name}"
    open_positions(account_name).each do |pos_id|
      pos = position(pos_id)
      last = @lvc.last(pos.sec_id)
      action "mark position: #{pos_id} @ #{last}"
      pos.mark(last)
    end
  end

#  def update_wave_support(account_name)
#    action "Update wave support for account: #{account_name}"
#    open_positions(account_name).each do |pos_id|
#      pos = position(pos_id)
#      pos.update_stop_price if pos.trailing_stop_type == "wave"
#    end
#  end

  def status_change(pos_id, status)
    show_info "PortfolioMgr#status_change(#{pos_id},#{status})"
    action "set position(#{pos_id}) status to #{status}"
    position(pos_id).set_status(status)
  end

  def trades_for_entry(entry_id)
    show_info "PortfMgr#trades_for_entry(#{entry_id})"
    entry = EntryProxy.new(entry_id: entry_id)
    show_info "PortfMgr#trades_for_entry: entry.attributes=#{entry.dump}"
    entry.trailing_stop_type ||= account.trailing_stop_type
    trans = StringIO.new
    unless entry.valid?
      warn "trades_for_entry: entry NOT valid  entry=#{entry.dump}"
      raise InvalidEntryError, "trades_for_entry:  entry=#{entry.dump}"
    end
    if scaling_in?(entry)
      debug "PortfMgr#trades_for_entry: scaling in"
      trade_list = trade_for_open_position(entry)
    else
      debug "PortfMgr#trades_for_entry: NOT scaling in"
      trade_list = trades_for_accounts(entry)
    end
    debug "trades_for_entry: trade_list=#{trade_list}"
    trade_list
  end

  def create_trade(account,entry,risk_per_share)
      debug "create_trade(account,#{entry.attributes},risk_per_share)"
      trade = Trade.new(account.account_name, entry.entry_id)
      trade.pos_id             = entry.pos_id if MiscHelper::valid_id?(entry.pos_id.to_i)
      debug "trade.pos_id = #{trade.pos_id}" if MiscHelper::valid_id?(entry.pos_id.to_i)
      trade.init_risk_share    = risk_per_share.round(3)
      trade.side               = entry.side
      trade.ticker             = entry.ticker
      trade.tags               = entry.tags
      trade.notes              = entry.notes
      trade.sec_id             = entry.sec_id
      trade.setup_id           = entry.setup_id
      trade.setup_src          = entry.setup_src
      trade.entry_signal       = entry.entry_signal
      trade.trade_type         = entry.trade_type
      trade.rps_exit           = entry.rps_exit
      trade.tgt_gain_pts       = entry.tgt_gain_pts
      trade.entry_stop_price   = entry.entry_stop_price
      trade.trailing_stop_type = entry.trailing_stop_type
      if account.trailing_stop_type == "timed"
        trade.time_exit        = account.time_exit
        trade.trailing_stop_type = "timed"
      end
      trade.support            = entry.support
      trade.work_price         = entry.work_price
      trade.limit_price        = entry.limit_price
      trade.broker             = account.broker
      trade.atr_factor         = account.atr_factor
      trade.broker_account     = account.broker_account
      trade.init_risk_position = @money_mgr.send("#{account.equity_model}_risk_dollars",
                                          account).round(2)
      trade.mm_size            = @money_mgr.send("#{account.money_mgr}_size", trade)

      # these accounts used for analysis - paper accounts only
      if account.override?
        trade.trailing_stop_type = account.trailing_stop_type
        trade.time_exit          = account.time_exit if account.time_exit
      end

      unless trade.within_capital_limit?(account.capital_next_trade)
        warn "trade NOT within Cap Limit: account=#{account.account_name}  tkr=#{trade.ticker} mm_size=#{trade.mm_size}  limit_price=#{trade.limit_price} exceeds capital limit: #{account.capital_next_trade}"
        init_size = trade.mm_size
        adj_size =  (account.capital_next_trade / trade.limit_price).to_i
        trade.mm_size = (adj_size > 25) ? adj_size : 0
        warn "trade size adjusted to meet Cap limit: #{init_size} -> #{trade.mm_size}"
      end
      show_info "return trade: #{trade.attributes}"
      trade
  end

  def set_target_exit(pos)
    debug "PortfolioMgr#set_target_exit pos_id=#{pos.pos_id} trade_type=#{pos.trade_type}"
    pos_id = pos.pos_id
    return unless position_is_open?(pos_id)
    return if position_is_timed?(pos_id)
    if pos.trade_type == 'DayTrade'
      price = pos.avg_entry_px + pos.sidex * pos.tgt_gain_pts
      @trader.create_target_exit(pos_id,pos.sec_id,pos.side,price)
    end
  end


  ###############
  private
  ###############

  def scaling_in?(entry)
    warn "PortfolioMgr: scaling_in? - need some code"
    debug "scaling_in?: entry.attributes = #{entry.attributes}"
    return false if new_position?(entry.attributes)
    pos = position(entry.pos_id)
    return true if @account_mgr.get_account(pos.account_name).pyramid_positions?
    false
  end

  def account_list
    @account_mgr.accounts  #.collect { |account| account['status'] == "active" }
  end

  def new_position?(params)
    attribs = Hash[params.map{|(k,v)| [k.to_sym,v]}]
    puts "new_position?(#{attribs})"
    puts "new_position?: attribs[:pos_id] = #{attribs[:pos_id]}"
    rtn = MiscHelper::valid_id?(attribs[:pos_id]) && position_is_open?(attribs[:pos_id])
    puts "new_position?(attribs) returns #{!rtn}"
    !rtn
  end

  def trade_for_open_position(entry)
    show_info "trade_for_open_position(entry) NEED SOME CODE HERE"
    trade_list = []
    debug "pos = position(#{entry.pos_id})"
    pos = position(entry.pos_id)
    risk_per_share = pos.init_risk_share
    account = @account_mgr.get_account(pos.account_name)
    debug "trade_for_open_position: create_trade(account,entry,#{risk_per_share})"
    trade = create_trade(account,entry,risk_per_share)
    trade_list << trade
  end

  def trades_for_accounts(entry)
    debug "PortfolioMgr#trades_for_accounts:  entry.trade_type=#{entry.trade_type.downcase}"
    trade_list = []
    account_list.each do |account|
      show_info "PortfMgr#trades_for_accounts: account=#{account.account_name}"
      next unless @account_mgr.valid_trading_account?(account)
      unless (account.setups.include?(entry.setup_src)  || account.setups.include?("all"))
        show_info "setup src: #{entry.setup_src} not configured for account #{account.account_name}"
        next
      end
      unless (account.trade_type.downcase.split(":").include?(entry.trade_type.downcase) || account.trade_type.downcase == "all")
        show_info "account #{account.account_name} NOT configured for trade_type: #{entry.trade_type}"
        next
      end
      unless account.longshort.downcase.split(":").include?(entry.side.downcase)
        show_info "account #{account.account_name} NOT configured for side: #{entry.side}"
        next
      end
      puts "account.pyramid_positions? = #{account.pyramid_positions?}"
      puts "entry.pyramid? = #{entry.pyramid?}"
      unless account.pyramid_positions? && entry.pyramid?
        if account.has_open_position?(entry.sec_id)
          warn "#{account.account_name} has_open_position?(#{entry.sec_id})"
          next
        end
      end
      risk_per_share = @money_mgr.init_risk_share(account, entry)
      unless risk_per_share > 0
        warn "risk per share is 0"
        next
      end
      trade = create_trade(account,entry,risk_per_share)
      show_info "return trade:: #{trade.attributes}" if trade
      trade_list << trade if trade
    end
    trade_list
  end 

  def set_scale_in_alerts(pos)
    warn "set_scale_in_alerts(pos) - need some code"
  end

#  def create_timed_exit(pos_id, time_exit)
#    debug "create_timed_exit(#{pos_id}, #{time_exit})"
#    raise InvalidTradeError.new, "could not set exit time(#{time_exit})" unless time_exit =~ /\d+d/
#    days = time_exit.to_i
#    exit_day = DateTimeHelper::future_trade_day(days)
#    @store.create_timed_exit(pos_id, exit_day)
#  rescue InvalidTradeError => e
#    warn "could not create timed exit for pos: #{pos_id}"
#    warn e.message
#  end

  def close_position(pos)
    action "PortfolioMgr#close_position(#{pos})"
    pos.close_position
    @store.close_position(pos.account_name,pos.pos_id)
    #@risk_mgr.close_position_exit_alerts(pos)
    @alert_mgr.close_alerts(self.class, pos.sec_id, pos.pos_id)
  end

  def cancel_position(position)
    action "PortfolioMgr#cancel_position: account: #{position.account_name}  pos_id: #{position.pos_id}"
    position.set_status("canceled")
    @store.cancel_position(position.account_name,position.pos_id)
  end

  def open_position(account_name, pos_id)
    debug "PortfolioMgr#open_position(#{account_name},#{pos_id})"
    position(pos_id).set_status("open")
    @store.open_position(account_name, pos_id)
  end

  def initialize_position(account_name, pos_id)
    @store.initialize_position(account_name, pos_id)
  end

  def update_position(account_name, pos_id, order_qty, escrow)
    @store.update_position(account_name, pos_id, order_qty, escrow)
  end

  def account(name)
    @accounts[name] ||= @account_mgr.get_account(name)
  end

  def new_position(params)
    debug "new_position(#{params})"
    pos = PositionProxy.new(params)
    #pos.set_status("init")
    @store.new_position(params[:account_name], pos.pos_id)
    pos.pos_id
  end

  def valid_trade?(trade, transcript=StringIO.new)
    rtn = true
    #puts "account names = #{active_account_names}"
    unless %w(long short).include? trade.side
      transcript.puts "trade: unknown side: #{trade.side}"
      rtn = false
    end
    unless (trade.init_risk_position > 0.0)
      transcript.puts "trade: init_risk_position NOT > 0.0"
      rtn = false
    end
    unless (trade.init_risk_share > 0.0)
      transcript.puts "trade: init_risk_share NOT > 0.0"
      rtn = false
    end
    unless (trade.mm_size > 0.0)
      transcript.puts "trade: mm_size NOT > 0.0"
      rtn = false
    end
    rtn
  end

  def valid_position?(pos_params, transcript=StringIO.new)
    rtn = true
    unless pos_params[:ticker] =~ /\w+/
      transcript.puts "position: bad ticker: #{pos_params[:ticker]}"
      rtn = false
    end
    unless %w(long short).include? pos_params[:side]
      transcript.puts "position: unknown side: #{pos_params[:side]}"
      rtn = false
    end
    unless pos_params[:sec_id] || (pos_params[:sec_id] > 0)
      transcript.puts "position: bad sec_id: #{pos_params[:sec_id]}"
      rtn = false
    end
    unless (pos_params[:quantity] > 0.0)
      transcript.puts "position: quantity NOT > 0.0"
      rtn = false
    end
    unless (pos_params[:account_name] =~ /\w+/)
      transcript.puts "position: account_name wrong"
      rtn = false
    end
    unless (pos_params[:price] > 0.0)
      transcript.puts "position: price NOT > 0.0"
      rtn = false
    end
    unless (pos_params[:price] > 0.0)
      transcript.puts "position: price NOT > 0.0"
      rtn = false
    end
    current_risk_share =  pos_params.fetch(:current_risk_share) {
      transcript.puts "position: current risk (#{pos_params[:current_risk_share]} missing"
      rtn = false
    }
    unless current_risk_share > 0.0
      transcript.puts "position: current risk NOT > 0.0"
      rtn = false
    end
    trailing_stop_type = pos_params.fetch(:trailing_stop_type) {
      transcript.puts "position: trailing stop type (#{pos_params[:trailing_stop_type]}) missing"
      rtn = false
    }
    debug "======2 trailing_stop_type = #{trailing_stop_type}"
    unless TrailingStops.include? trailing_stop_type
      transcript.puts "position: trailing stop type (#{pos_params[:trailing_stop_type]} not known"
      rtn = false
    end

    debug "======2 rtn = #{rtn}"
    rtn
  rescue => e
    puts e
    puts e.message
    print e.backtrace.join("/n")
    transcript.puts "position validation failed (#{pos_params})"
    rtn = false
  end

  def active_account_names
    @store.active_account_names
  end
end

