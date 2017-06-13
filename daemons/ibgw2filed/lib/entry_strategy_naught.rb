require "entry_strategy_base"
require "log_helper"

class EntryStrategyNaught < EntryStrategyBase
  include LogHelper

  def initialize
    super "naught"
  end

  def goes_long?
    false
  end

  def buy?(sec_id)
    false
  end

  def sell?(sec_id)
    false
  end
end
