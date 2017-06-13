$: << "#{ENV['ZTS_HOME']}/lib"

require "auto_trader_base"
require "auto_trader_ema34_crossover"
require "auto_trader_naught"
#require "redis_store"
require "log_helper"
require "string_helper"

class AutoTraderMgr # < RedisStore
  include LogHelper
  include Store

  attr_reader :auto_traders

  def initialize
    show_info "AutoTraderMgr#initialize"
    super
    @auto_traders = instantiate_auto_traders
  end

  def whoami
    self.class.to_s
  end

  def sec_ids
    auto_traders.map { |at| at.watchlist }
  end

  def check_for_entries(bar)
    auto_traders.map { |at| puts "#{at.name}"; at.run_bar_for_entries(bar).map { |entry| entry.entry_id } }.flatten
  end

  #######
  private
  #######

  def instantiate_auto_traders
    show_action "AutoTraderMgr#instantiate_auto_traders"
    raw = redis.keys "auto_trader:*"
    show_action "AutoTraderMgr#instantiate_auto_traders raw=#{raw}"
    at_names = (raw.map { |r| r[/auto_trader:(.*)/,1] }).map { |s| s.gsub(":","_") }
    at_names.map do |sn|
      show_info "setting up strategy #{sn}"
      strategy_class = self.class.const_get("AutoTrader#{sn.camelize}")
      strategy_class.new
    end
  rescue
    AutoTraderNaught.new
    alert "AutoTrader not found! : error instantiating auto trade"
  end

  #def redis
  #  @redis ||= RedisFactory.instance.client
  #end

end
