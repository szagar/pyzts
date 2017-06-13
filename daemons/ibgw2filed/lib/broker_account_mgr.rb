#$: << "#{ENV['ZTS_HOME']}/lib"

require "broker_account_mgr_store"
#require "zts_constants"
#require "log_helper"
require "pp"

class BrokerAccountMgr
  #include ZtsConstants
  #include LogHelper

  def initialize(store=BrokerAccountMgrStore.new)
    @store = store
  end
  
  def info
    store_name
  end

  def accounts
    @store.accounts
  end

  def summary
    puts "   account      cash availFnds maintMgn   Real  UnReal excsLiq mkt_val   reg_t   power"
    accounts.each do |account|
      #pp account
      printf "%10s%10.0f%10.0f%8.0f%8.0f%8.0f%8.0f%8.0f%8.0f%8.0f\n",
             account.AccountCode,
             account.CashBalance,
             account.FullAvailableFunds_S,
             account.MaintMarginReq_S,
             account.RealizedPnL,
             account.UnrealizedPnL,
             account.FullExcessLiquidity_S,
             account.StockMarketValue,
             account.RegTMargin_S,
             account.BuyingPower
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
