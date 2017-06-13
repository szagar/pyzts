#$: << "#{ENV['ZTS_HOME']}/lib"

require "account_mgr_store"
require "zts_constants"
require "log_helper"

class AccountMgr
  include ZtsConstants
  #include LogHelper

  def initialize(persister=AccountMgrStore.new)
    @persister      = persister
  end
  
  def info
    persister_name
  end

  def accounts(args=nil)
    @persister.accounts(*args)
  end

  def get_account(name)
    @persister.account(name)
  end

  def summary
    tots = {}
    puts "      account         cash acct_eqty locked_in    escrow debit_bal exces_liq   mkt_val     reg_t     power"
    accounts.each do |account|
      ah = account.attributes
      broker = ah["broker"]
      ah.keys.each do |fld|
        #tots[fld] = (tots.fetch(fld) {0.0}).to_f + ah[fld] unless %w(account_name broker broker_account).include? fld
        tots[broker] = tots.fetch(broker) { Hash.new }
        # broker_data = tots.fetch(broker) { Hash.new }
        tots[broker][fld] = (tots[broker].fetch(fld) {0.0}).to_f + ah[fld] if ah[fld].is_a? Numeric
      end
      printf "%16s%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f  %s\n",
             account.account_name,
             account.cash,
             account.account_equity,
             account.long_locked_in,
             account.escrow,
             account.debit_balance,
             account.excess_liquidity,
             account.long_market_value,
             account.reg_t_intraday,
             account.buying_power,
             account.broker
    end
    #puts "tots=#{tots}"
    puts "\n\n      account         cash acct_eqty locked_in    escrow debit_bal exces_liq   mkt_val     reg_t     power"
    tots.keys.sort.each do |b|
      #puts tots[b]
      printf "%16s%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f%10.0f  %s\n",
             b,
             tots[b]["cash"],
             0.0,
             tots[b]["long_locked_in"] || 0.0,
             tots[b]["escrow"],
             tots[b]["debit_balance"],
             0.0,
             tots[b]["debit_balance"],    #excess_liq
             tots[b]["long_market_value"] || 0.0,
             0.0,
             0.0
    end
  end

  def accounts_in_csv
    data   = {}
    fields = {}
    result = []
    accounts.each do |a|
      data[a['name']] = {}
      a.each do |k,v|
        data[a['name']][k] = v
        fields[k] = true
      end
    end
    f_order = fields.keys.sort
    data.keys.sort.each do |account|
      rec = []
      f_order.each do |f|
         rec << data[account][f]
      end
      result << rec.join(",")
    end
    result
  end

  def valid_trading_account?(account)
    return true if %w(VanTharp Martha).include?(account.money_mgr)
    warn "Account #{account.account_name} does not have valid money_mgr configured(#{account.money_mgr}), should be VanTharp or Martha"
    return false
  end

  def method_missing(methId, *args, &block)
    case methId.id2name
    when 'equity_value', 'position_percent', 'cash', 'core_equity', 'realized',
         'unrealized', 'reliability', 'expectancy', 'sharpe_ratio',
         'vantharp_ratio', 'maxRp', 'maxRm', 'risk_dollars', 'atr_factor',
         'total_commissions'
      @persister.getter(@account, methId.id2name).to_f
    when 'account_id', 'min_shares', 'lot_size', 'no_trades',
         'no_trades_today', 'no_open_positions'
      @persister.getter(@account, methId.id2name).to_i
    when 'money_mgr', 'broker', 'equity_model', 'date_first_trade',
         'date_last_trade', 'status'
      @persister.getter(@account, methId.id2name)
    else
      super
    end
    #@persister.send(methId, @account)
  end

  def db_parms
   { 
    } 
  end

  private

  def persister_name
    @persister.whoami
  end
end
