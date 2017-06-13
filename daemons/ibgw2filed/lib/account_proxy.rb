#$: << "#{ENV['ZTS_HOME']}/lib"

require "account_store"
require "position_store"
require "transaction_store"
require "zts_constants"
require "log_helper"
require "date_time_helper"

module Zts
  module Error
  end
end

class AccountProxy
  include ZtsConstants
  include LogHelper

  attr_reader :account_name

  def initialize(params, persister=AccountStore.new,
                         position_store=PositionStore.instance,
                         xact_store=TransactionStore.instance)
    @persister      = persister
    @position_store = persister  #position_store
    @xact_store     = xact_store
    if @persister.exists?(params[:account_name]) 
      @account_name   = params[:account_name]
    else
      caller_locations(1, 1).first.tap { |loc| action "Creating new account: #{params[:account_name]} from: #{loc.path}:#{loc.lineno}"}
      #warn "Creating new accounts: #{params}"
      create_account(params) 
    end

    #x= @persister.exists?(params[:account_name])
    #@account_name      = (x) ?
    #                       params[:account_name] :
    #                       create_account(params) 
  end
  
  def set_transaction_store(store)
    @xact_store = store
  end

  def validate(params)
    params.fetch(:account_name) { raise "missing account name"}
    unless (params[:account_name][/\w/])
      raise("missing account name")
    end
    true
  end

  def create_account(params={}, force=false)
    debug "AccountProxy#create_account(#{params})"
    cash = params.delete(:cash) {|k| 0.0}
    set_defaults(params)
    validate(params) && @account_name=@persister.create(params)
    deposit(cash, DateTimeHelper::integer_date, note="initial funding")
    account_name
  end

  def info
    persister_name
  end

  def attributes(fields=members)
    result = {}
    fields.each do |name|
      result[name] = self.send name
    end
    result
  end

  def trailing_stop_type
    stop_type = @persister.getter(@account_name, "trailing_stop_type")
    TrailingStops.include?(stop_type) ? stop_type : nil
  end

  def method_missing(methId, *args, &block)
    #puts "AccountProxy#method_missing(#{methId}, #{args}) #{methId.class}"
    case methId.id2name
    when /=/
      #puts "AccountProxy#method_missing(#{methId}, #{args}) #{methId.class}"
      @persister.setter(@account_name,methId.id2name.chomp("="),args)
    when 'position_percent', 'cash', 'realized', 'percent_capital_per_trade',
         'unrealized', 'reliability', 'expectancy', 'sharpe_ratio',
         'vantharp_ratio', 'maxRp', 'maxRm', 'risk_dollars', 'atr_factor',
         'total_commissions', 'long_locked_in', 'escrow', 'debit_balance',
         'initial_margin_rate', 'maint_margin_rate'
      self.class.send(:define_method, methId) do
        @persister.getter(@account_name, methId.id2name).to_f.round(2)
      end
      @persister.getter(@account_name, methId.id2name).to_f.round(2)
    when 'account_id', 'min_shares', 'lot_size', 'no_trades',
         'no_trades_today', 'no_open_positions', 'number_positions',
         'time_exit'
      self.class.send(:define_method, methId) do
        @persister.getter(@account_name, methId.id2name).to_i 
      end
      @persister.getter(@account_name, methId.id2name).to_i
    when 'money_mgr', 'broker', 'broker_account', 'equity_model',
         'date_first_trade', 'date_last_trade', 'status', 'pyramid_positions',
         'override', 'trade_type', 'longshort'
      self.class.send(:define_method, methId) do
        @persister.getter(@account_name, methId.id2name)
      end
      @persister.getter(@account_name, methId.id2name)
    when 'account_name'
      self.class.send(:define_method, methId) do
        @persister.getter(@account_name, methId.id2name)
      end
      @persister.getter(@account_name, methId.id2name)
    else
      super
    end
    #@persister.send(methId, @account_name)
  end

  def summary
   ["name                : #{account_name}",
    "cash                : #{cash}",
    "account_equity      : #{account_equity}",
    "long_locked_in      : #{long_locked_in}",
    "escrow              : #{escrow}",
    "debit_balance       : #{debit_balance}",
    "excess_liquidity    : #{excess_liquidity}",
    "long_market_value   : #{long_market_value}",
    "reg_t_intraday      : #{reg_t_intraday}",
    "buying_power        : #{buying_power}"  ]
  end

  def deposit(amount, date, note="")
    action "Deposit (date: #{date} account: #{account_name}) amount: #{amount}  note: #{note}"
    @xact_store.deposit(@account_name, amount, date, note)
    self.cash   += amount.to_f.round(2)
  end

  def withdraw(amount, date, note="")
    action "Withdraw (date: #{date} account: #{account_name}) amount: #{amount}  note: #{note}"
    @xact_store.withdraw(@account_name, amount, date, note)
    self.cash   -= amount.to_f.round(2)
  end

  def add_setup(setup_name)
    action "Add setup (account: #{account_name}) setup: #{setup_name}"
    @persister.add_setup(@account_name, setup_name)
  end

  def setups
    @persister.setups(@account_name)
  end

  def rm_setup(setup_name)
    action "Remove setup (account: #{account_name}) setup: #{setup_name}"
    show_action "Account#rm_setup(#{account_name}): #{setup_name}"
    @persister.rm_setup(@account_name, setup_name)
  end

  def funds_moved_to_escrow?(amount)
    action "Funds moved to escrow (account: #{account_name}) amount: #{amount}"
    show_action "Account(#{account_name}) reserve escrow: #{amount}"
    rtn = false
    
    if funds_available?(amount)
      move_funds_for_escrow(amount)
      rtn = true
    end
    summary.each do |line|
      show_status line
    end
    rtn
  end

  def release_excess_escrow(amount)
    action "Release excess escrow (account: #{account_name}) amount: #{amount}"
    old_escrow = escrow
    old_cash   = cash

    self.cash   += amount.to_f.round(2)
    self.escrow -= amount.to_f.round(2)

    show_info "release_excess_escrow: escrow: #{old_escrow} ==> #{escrow}"
    show_info "release_excess_escrow: cash  : #{old_cash} ==> #{cash}"
  end

  # funding
  def account_equity
    (cash + escrow + long_market_value - debit_balance).round(2)
  end

  def long_market_value
    (@position_store.open_positions_by_account(@account_name).inject(0) { |value,p|
      value + (p['position_qty'].to_f * p['mark_px'].to_f)
    }).to_f.round(2)
  end

  def long_locked_in
    debug "AccountProxy#long_locked_in: @account_name=#{@account_name}"
    (@position_store.open_positions_by_account(@account_name).inject(0) { |cost,p|
      cost + (p['position_qty'].to_f * p['current_stop'].to_f)
    }).to_f.round(2)
  end

  def reg_t_intraday
    ((long_market_value + escrow) * initial_margin_rate).round(2)
  end

  def excess_liquidity
    (account_equity - reg_t_intraday).round(2)
  end

  def buying_power
    (excess_liquidity / initial_margin_rate).to_f.round(2)
  end

  def funds_available?(amount)
    #puts "AccountProxy#funds_available? (#{buying_power} >= #{amount})"
    (buying_power >= amount)
  end


  def capital_next_trade
    debug "cash                      = #{cash}"
    debug "escrow                    = #{escrow}"
    debug "long_market_value         = #{long_market_value}"
    debug "debit_balance             = #{debit_balance}"
    debug "excess_liquidity          = #{excess_liquidity}"
    debug "reg_t_intraday            = #{reg_t_intraday}"
    debug "initial_margin_rate       = #{initial_margin_rate}"
    debug "percent_capital_per_trade = #{percent_capital_per_trade}"

    rtn = buying_power * percent_capital_per_trade / 100.0

    debug "capital_next_trade        = #{rtn}"
    #account_equity * percent_capital_per_trade / 100.0
    rtn
  end

  def db_parms
   { id: account_id, account_name: @account_name, money_mgr: money_mgr,
     position_percent: position_percent, escrow: escrow, debit_balance: debit_balance,
     cash: cash, net_deposits: net_deposits, 
     #available_funds: available_funds,
     long_locked_in: long_locked_in, atr_factor: atr_factor, equity_model: equity_model,
     broker: broker, broker_account: broker_account,
     realized: realized, unrealized: unrealized,
     no_trades: no_trades, no_trades_today: no_trades_today,
     no_open_positions: no_open_positions, reliability: reliability,
     expectancy: expectancy, sharpe_ratio: sharpe_ratio,
     vantharp_ratio: vantharp_ratio, maxRp: maxRp, maxRm: maxRm,
     date_first_trade: date_first_trade, date_last_trade: date_last_trade,
     status: status, risk_dollars: risk_dollars
    } 
  end

  def open_position_ids
    @position_store.open_position_ids(@account_name)
  end

  def open_positions
    @position_store.open_positions_by_account(@account_name)
  end

  def dump
    @persister.dump(@alert_id)
  end

  def transfer_payment(total_cost,equity_value)
    action "Transfer payment(account: #{account_name}) total_cost: #{total_cost}, equity_value: #{equity_value}"
    current_cash   = cash
    current_escrow = escrow
    self.escrow         = [(escrow - total_cost),0].max.round(2)
    show_action "Transfer payment(#{account_name}): escrow  #{current_escrow} => #{escrow}"
    show_action "Transfer payment(#{account_name}): #{[(cash - (total_cost - (current_escrow - escrow))),0].max.round(2)} from cash"
    self.cash           = [(cash - (total_cost - (current_escrow - escrow))),0].max.round(2)
    show_action "Transfer payment(#{account_name}): #{(total_cost - (current_cash - cash) - (current_escrow - escrow)).round(2)} from debit"
    self.debit_balance += (total_cost - (current_cash - cash) - (current_escrow - escrow)).round(2)
  end

  def adj_for_proceeds(total_cost,equity_value)
    action "Adjust for proceeds (account: #{account_name}) total_cost: #{total_cost}, equity_value: #{equity_value}"
    free_escrow(total_cost)
  end

  def has_open_position?(sec_id)
    sids = @position_store.open_positions_by_account(@account_name)
                          .each_with_object({}) { |ph,sh| 
      sh[ph["sec_id"]] = true
    }
    sids.fetch(sec_id.to_s) {false}
  end

  def pyramid_positions?
    pyramid_positions == "true" ? true : false
  rescue 
    false
  end

  def override?
    override == "on"
  end
 
  ##########
  private
  ##########

  def free_escrow(amount)
    action "Free escrow (account: #{account_name}) amount: #{amount}"
    old_debit_balance  = debit_balance
    old_cash           = cash
    old_escrow         = escrow
    actual_amount      = [escrow,amount].min

    self.escrow        = (escrow - actual_amount).round(2)
    self.debit_balance = [debit_balance-actual_amount,0].max.round(2)
    self.cash         += amount - (old_debit_balance - debit_balance)

    show_info "Free escrow(#{account_name}): debit_balance  #{old_debit_balance} => #{debit_balance}"
    show_info "Free escrow(#{account_name}): cash           #{old_cash} => #{cash}"
    show_info "Free escrow(#{account_name}): escrow         #{old_escrow} => #{escrow}"
  end

  def move_funds_for_escrow(amount)
    action "Move funds (account: #{account_name}) amount: #{amount}"
    old_cash        = cash
    self.cash           = [old_cash - amount, 0].max.round(2)
    self.debit_balance += [amount - old_cash, 0].max.round(2)
    self.escrow += amount.to_f.round(2)

    show_info "Account(#{account_name}) cash portion      : #{[old_cash,amount].min.round(2)}"
    show_info "Account(#{account_name}) borrow from margin: #{[amount - old_cash, 0].max.round(2)}"
    show_info "Account(#{account_name}) add to escrow     : #{amount.to_f.round(2)}"
    show_info "Account(#{account_name}) cash              : #{old_cash} ==> #{cash}"
  end


  def persister_name
    @persister.whoami
  end

  def set_defaults(params)
    params[:percent_capital_per_trade] ||= 10
    params[:initial_margin_rate] ||= INITIAL_MARGIN
    params[:maint_margin_rate]   ||= MAINTENANCE_MARGIN
    params[:trailing_stop_type]  ||= ""
    params[:broker]              ||= 'dumbfuck'
    params[:broker_account]      ||= '123456789'
    params[:cash]                ||= 0.0
    params[:escrow]              ||= 0.0
    params[:debit_balance]       ||= 0.0
    params[:position_percent]    ||= 0.0
    params[:net_deposits]        ||= 0.0
    params[:net_withdraws]       ||= 0.0
    params[:total_commissions]   ||= 0.0
    params[:atr_factor]          ||= 0.0
    params[:min_shares]          ||= 0.0
    params[:lot_size]            ||= 1
    params[:equity_model]        ||= "RTEM"
    params[:number_positions]    ||= 0
    params[:risk_dollars]        ||= 0.0
    params[:reliability]         ||= 0.0
    params[:expectancy]          ||= 0.0
    params[:sharpe_ratio]        ||= 0.0
    params[:vantharp_ratio]      ||= 0.0
    params[:realized]            ||= 0.0
    params[:unrealized]          ||= 0.0
    params[:maxRp]               ||= 0.0
    params[:maxRm]               ||= 0.0
    params[:date_first_trade]    ||= ""
    params[:date_last_trade]     ||= ""
    params[:status]              ||= "pending"
    params[:trade_type]          ||= ""
    params[:longshort]           ||= ""
  end

  def net_deposits
    @persister.net_deposits(@account_name)
  end

  def net_withdraws
    @persister.net_withdraws(@account_name)
  end

  def cost_positions
    cost = (@position_store.open_positions_by_account(@account_name).inject(0) { |cost,p|
      cost + p['commissions'].to_f +
             (p['position_qty'].to_f * p['avg_entry_px'].to_f)
    }).to_f
    cost
  end

  def proceeds_positions
    (@position_store.open_positions_by_account(@account_name).inject(0) { |proceeds,p|
      proceeds + p['realized'].to_f
    }).to_f
  end

  def initial_margin(amount=0.0)
    initial_margin_rate * (long_market_value + escrow + amount)
  end

  def maintenance_margin
    maint_margin_rate * (long_market_value + escrow)
  end

  def members
    @persister.members(@account_name)
  end
end
