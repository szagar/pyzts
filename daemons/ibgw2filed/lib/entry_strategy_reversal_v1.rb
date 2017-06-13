require "entry_strategy_base"
require "last_value_cache"
require "log_helper"

class EntryStrategyReversalV1 < EntryStrategyBase
  include LogHelper

  attr_reader :lvc

  def initialize
    @lvc = LastValueCache.instance
    super "reversal_v1"
  end

  def goes_long?
    true
  end

  def buy?(sec_id)
    show_info "#{self.class}#buy?: #{lvc.close(sec_id)} > #{lvc.ema(sec_id,'high','34')}"
    lvc.close(sec_id) > lvc.ema(sec_id,"high","34")
  end

  def sell?(sec_id)
    show_info "#{self.class}#buy?: #{lvc.close(sec_id)} < #{lvc.ema(sec_id,'low','34')}"
    lvc.close(sec_id) < lvc.ema(sec_id,"low","34")
  end

  def config_buy_entry(setup)
    sec_id, ticker = parse_setup(setup)
    results = super(sec_id)
    results[:entry_stop_price] = (lvc.last(sec_id) + 0.025).round(2)
    results
  end
end

