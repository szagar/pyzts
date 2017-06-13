$: << "#{ENV['ZTS_HOME']}/lib"
require "systematic_store"
#require "setup_mgr"
require "log_helper"
require "singleton"

class Systematic
  include LogHelper
  include Singleton

  attr_reader :store   #, :setup_mgr

  def initialize
    @store = SystematicStore.new
    #@setup_mgr = SetupMgr.new
  end

#  def entry_buy_signals
#    signals = []
#    strategies.each do |strategy|
#      next unless strategy.goes_long?
#      strategy.watchlist.each do |sec_id|
#        signals << strategy.config_buy_entry(sec_id) if strategy.buy?(sec_id)
#      end
#    end
#    signals
#  end
#
#  def entry_sell_signals
#    signals = []
#    strategies.each do |strategy|
#      next unless strategy.goes_short?
#      strategy.watchlist.each do |sec_id|
#        signals << strategy.config_sell_entry(sec_id) if strategy.sell?(sec_id)
#      end
#    end
#    signals
#  end
#
#  def setups
#    entry_buy_signals.map do |entry|
#      setup_mgr.config_setup(entry)
#    end
#  end

  def setups(filter="")
    debug "Systematic#setups(#{filter})"
    setups = []
    strategies(filter).each do |strategy|
      debug "Systematic#setups strategy=#{strategy}"
      strategy.watchlist.each do |setup|
        sec_id, ticker = strategy.parse_setup(setup)
        setups << strategy.config_buy_entry(setup)  if strategy.buy?(sec_id)
      end
    end
    puts "setups=#{setups}"
    setups
  end

  def strategies(filter)
    debug "Systematic#strategies filter=#{filter}"
    Array(store.strategies(filter))
  end

  ############
  private
  ############

end

