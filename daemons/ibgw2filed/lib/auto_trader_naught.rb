require "auto_trader_base"
require "log_helper"

class AutoTraderNaught < AutoTraderBase
  include LogHelper

  def initialize
    super "naught"
  end

  def watchlist
    []
  end
end
