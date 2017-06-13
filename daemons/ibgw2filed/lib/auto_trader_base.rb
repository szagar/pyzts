$: << "#{ENV['ZTS_HOME']}/lib"

require "s_m"
require "store_mixin"
#require "redis_store"
require "log_helper"
require "string_helper"

class MissingMethodDefinition < StandardError; end

class AutoTraderBase # < RedisStore
  include LogHelper
  include Store

  attr_reader :name, :redis_name, :positions, :sec_master

  def initialize(name)
    @name = name
    show_info "AutoTraderStore#initialize"
    @sec_master = SM.instance
    #super
    @positions = at_positions
  end

  def whoami
    self.class.to_s
  end

  def watchlist
    redis.smembers pk
  end

  #def run_bar_for_entries(bar)
  #  raise MissingMethodDefinition.new, "missing method definition for auto trader: #{name}"
  #end

  def run_bar_for_entries(bar)
    entries = []
    watchlist.each do |sec_id|
      set_pre_test_flags(sec_id,bar)
      entries << create_entry(config_buy_entry(sec_id,bar))  if goes_long?  and buy?(sec_id,bar)
      entries << create_entry(config_sell_entry(sec_id,bar)) if goes_short? and sell?(sec_id,bar)
      set_post_test_flags(sec_id,bar)
    end
    entries
  end

  #######
  private
  #######

  #def redis
  #  @redis ||= RedisFactory.instance.client
  #end

  def pk
    @redis_name ||= name.gsub("_",":")
    "auto_trader:#{redis_name}"
  end

  def at_positions
    pos_h = zero_position
    (redis.smembers redis_name).map do |pos_entry|
      sec_id, qty = pos_entry.split ":"
      pos_h[sec_id] = qty
    end
    pos_h
  end

  def zero_position
    pos_h = {}
    watchlist.each { |sec_id| pos_h[sec_id] = 0 }
  end

  def clr_flags(sec_id)
  end

  def set_pre_test_flags(sec_id,bar)
  end

  def set_post_test_flags(sec_id,bar)
  end

  def long?(sec_id)
    positions[sec_id] > 0 rescue false
  end

  def short?(sec_id)
    positions[sec_id] < 0 rescue false
  end

  def flat?(sec_id)
    positions[sec_id] == 0 rescue false
  end

  def goes_long?
    false
  end

  def goes_short?
    false
  end

  def buy?(sec_id)
    false
  end

  def sell?(sec_id)
    false
  end

  def long_setup?(sec_id)
    false
  end

  def short_setup?(sec_id)
    false
  end

  def tag
    "entry_strategy:#{whoami[/AutoTrader(.*)/,1]}" + "," + "setup_src:auto_trader"
  end

  def config_default_entry(ticker)
    { sec_id:             sec_master.sec_lookup(ticker),
      ticker:             ticker,
      entry_signal:       "pre-buy",
      trade_type:         "DayTrade",
      setup_src:          "auto_trader",
      trailing_stop_type: "manual",
      tags:               tag,
    }
  end

  def config_buy_entry(sec_id)
    config_default_entry(sec_id).merge!(side: "long")
  end

  def config_sell_entry(sec_id)
    config_default_entry(sec_id).merge!(side: "short")
  end

  def create_entry(setup)
    entry = EntryProxy.new(setup)
    entry.expire_at_next_close
    entry.status       = "open"
    entry.initial_risk = (entry.limit_price - entry.stop_loss_price).abs
    entry
  end
end
