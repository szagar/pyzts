$: << "#{ENV['ZTS_HOME']}/lib"
#require "systematic_store"
require "setup_mgr"
require "log_helper"
require "singleton"

class PreBuys
  include LogHelper
  include Singleton

  attr_reader :setup_mgr

  def initialize
    #@store = SystematicStore.new
    @setup_mgr = SetupMgr.new
  end

  def setups
    setups = []
    pre_buys.each do |pb|
      setups << config_buy_entry(pb)  if pb.buy?(sec_id)
      setups << config_sell_entry(pb) if pb.sell?(sec_id)
    end
    setups
  end

  ############
  private
  ############

  def pre_buys
#list << @setup_cfg.config_setup(ticker: "MTOR", setup_src: @setup_src, entry_signal: "pre-buy",
#                                trailing_stop_type: "support",
#                                entry_stop_price: 20.62, support: 20.02, tgt_gain_pts: 10)
    [ { ticker: "MTOR", setup_src: "prebuy_list", entry_stop_price: 20.62, support: 20.02, tgt_gain_pts: 10 },
      { ticker: "MTOR", setup_src: "prebuy_list", entry_stop_price: 20.62, support: 20.02, tgt_gain_pts: 10 },
    ]
  end

  def config_buy_entry(prebuy)
    prebuy.merge!( entry_signal: "pre-buy" )
    prebuy.merge!( trailing_stop_type: "support" )
    setup_mgr.config_setup(prebuy)
  end

  def config_sell_entry(prebuy)
  end
end

