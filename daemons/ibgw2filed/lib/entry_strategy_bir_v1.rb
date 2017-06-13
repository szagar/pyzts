require "entry_strategy_base"
require "last_value_cache"
require "log_helper"

class EntryStrategyBirV1 < EntryStrategyBase
  include LogHelper

  attr_reader :lvc

  def initialize
    @lvc = LastValueCache.instance
    super "bir_v1"
  end

  def goes_long?
    true
  end

  def buy?(sec_id)
    show_info "#{self.class}#buy?: #{lvc.close(sec_id)} > #{lvc.ema(sec_id,'high','34')}"
    lvc.close(sec_id) > lvc.ema(sec_id,"high","34")
  end

  def sell?(sec_id)
    false
  end

  def config_buy_entry(setup)
    puts "EntryStrategyBirV1#config_buy_entry(#{setup})"
    results = super(setup)
    sec_id, ticker = parse_setup(setup)
    results[:entry_stop_price] = (lvc.last(sec_id) + 0.025).round(2)
#    results[:pyramid]          = "true"
    results[:trade_type]       = "Trend"
    results
  end
end

