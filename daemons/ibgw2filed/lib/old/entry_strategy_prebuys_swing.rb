require "entry_strategy_base"
require "last_value_cache"
require "s_m"
require "log_helper"

class EntryStrategyPrebuysSwing < EntryStrategyBase
  include LogHelper

  attr_reader :sec_id, :lvc
  attr_reader :ticker, :entry_stop, :stop_loss, :points

#smembers systematic:prebuys:swing
# "ICGE:21.03:19.97:13"
# "TTEK:31.49:30.02:20"

  def initialize
    @lvc = LastValueCache.instance
    @sec_master = SM.instance
    super "prebuys_swing"
  end

  def goes_long?
    true
  end

  def parse_setup(setup)
    sec_id, ticker, entry_stop, stop_loss, points = setup.split(":")
    #@sec_id = sec_master.sec_lookup(ticker)
    [sec_id, ticker, entry_stop, support, points]
  end

  def buy?(setup)
    #parse_setup(setup)
    #lvc.close(sec_id) > entry_stop
    true
  end

  def sell?(setup)
    #parse_setup(setup)
    #lvc.close(sec_id) < entry_stop
    false
  end

  def config_buy_entry(setup)
    sec_id, ticker, entry_stop, support, points = parse_setup(setup)
    results = super(sec_id)
    results[:entry_stop_price] = entry_stop.to_f
    results[:entry_signal]     = "pre-buy"
    results[:trade_type]       = "Swing"
    results[:avg_run_pt_gain]  = points.to_f
    puts "EntryStrategyPrebuysSwing#config_buy_entry results=#{results}"
    results
  end
end

