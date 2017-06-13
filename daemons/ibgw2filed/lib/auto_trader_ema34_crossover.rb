$: << "#{ENV['ZTS_HOME']}/lib"

require "auto_trader_base"
require "last_value_cache"
#require "s_m"
require "log_helper"

class AutoTraderEma34Crossover < AutoTraderBase
  include LogHelper

  attr_reader :sec_id, :lvc
  #attr_reader :ticker, :entry_stop, :support, :points

  def initialize
    @lvc = LastValueCache.instance
    #@sec_master = SM.instance
    super self.class.to_s[/AutoTrader(.*)/,1].underscore
  end

  #####################
  private
  #####################

  def set_pre_test_flags(sec_id,bar)
  end

  def set_post_test_flags(sec_id,bar)
  end

  def clr_flags(sec_id)
  end

  def goes_long?
    true
  end

  def buy?(sec_id,bar)
    flat?(sec_id) && long_setup?(sec_id) && bar.close > lvc.ema(sec_id,"high",34)
true
  end

  def sell?(setup)
    #parse_setup(setup)
    #lvc.close(sec_id) < entry_stop
    false
  end

  def long_setup?(sec_id,bar)
  end

  def short_setup?(sec_id,bar)
  end

  def config_buy_entry(sec_id,bar)
    puts "config_buy_entry(#{sec_id},#{bar})"
    results = super(sec_id)
    results[:entry_stop_price] = (bar['close'].to_f + 0.05)
    results[:limit_price]      = results[:entry_stop_price] + 0.03
    results[:work_price]       = results[:limit_price]
    results[:stop_loss_price]  = bar.open
    results
  end

  def config_sell_entry(sec_id,bar)
    results = super(sec_id)
    results[:entry_stop_price] = (bar.last - 0.05)
    results[:limit_price]      = results[:entry_stop_price] - 0.03
    results[:work_price]       = results[:limit_price]
    results[:stop_loss_price]  = bar.open
    results
  end
end

