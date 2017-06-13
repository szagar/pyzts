require "portfolio_mgr"
require "transactions"

class Account
  attr_reader :account_name, :xact

  def initialize(account_name)
    @account_name = account_name
    @xact         = Transactions.new(account_name)
    @portf_mgr    = PortfolioMgr.instance
  end

  def net_invested
    xact.deposits - xact.withdraws + xact.mkt_money_transfers
  end

  def cash
    net_invested - (cost_long_positions * maint_margin)
  end

  def my_money
    [net_invested, liq_dollars].min
  end

  def maint_margin
    0.5
  end

  def init_margin
    0.5
  end

  def liq_dollars
    cash + current_market_value - debit_balance
  end

  def debit_balance
    cost_long_positions * (1 - init_margin)
  end

  def short_sale_collateral
    @portf_mgr.short_sale_collateral(account_name)
  end

  def current_market_value
    @portf_mgr.long_market_value(account_name)
  end

  def cost_long_positions
    @portf_mgr.cost_long_positions(account_name)
  end

end
