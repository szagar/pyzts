require "entry_strategy_base"
require "last_value_cache"
require "s_m"
require "log_helper"

class EntryStrategyPrebuysPosition < EntryStrategyBase
  include LogHelper

  attr_reader :lvc
  #attr_reader :ticker, :entry_stop, :support, :points, :sec_id

#smembers systematic:prebuys:position
# "ICGE:21.03:19.97:13"
# "TTEK:31.49:30.02:20"

  def initialize
    @lvc = LastValueCache.instance
    @sec_master = SM.instance
    super "prebuys_position"
  end

  def goes_long?
    true
  end

  def parse_setup(setup)
    sec_id, ticker, entry_stop, support, points = setup.split(":")
    #sec_id = sec_master.sec_lookup(ticker)
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
    puts "sec_id     = #{sec_id}"
    puts "ticker     = #{ticker}"
    puts "entry_stop = #{entry_stop}"
    puts "support    = #{support}"
    puts "points     = #{points}"
    results = super(sec_id)
    results[:entry_stop_price]   = entry_stop.to_f
    results[:entry_signal]       = "pre-buy"
    results[:trade_type]         = "Position"
    results[:support]            = support.to_f
    results[:trailing_stop_type] = "support"
    results[:tgt_gain_pts]       = points.to_f
    puts "EntryStrategyPrebuysPosition#config_buy_entry results=#{results}"
    puts "results=#{results}"
    results
  end
end

