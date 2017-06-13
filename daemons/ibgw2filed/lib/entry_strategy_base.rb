require "s_m"
require "store_mixin"

class EntryStrategyBase # < RedisStore
  include Store
  attr_reader :name, :sec_master

  def initialize(name)
    @name = name
    @sec_master = SM.instance
    show_info "EntryStrategyBase#initialize"
    #super
  end

  def whoami
    self.class.to_s
  end

  def watchlist
    puts "redis.smembers #{pk}"
    tickers = (redis.smembers pk)
puts "tickers=#{tickers}"
    tickers2 = tickers.map { |setup| 
puts "="
puts "setup=#{setup}"
      data = setup.split(":")
puts "data=#{data}"
      new_setup = (data.unshift sec_master.sec_lookup(data[0])).join(":") rescue next
      puts "new_setup: #{new_setup}"
      new_setup
    }
puts "tickers2=#{tickers2}"
    tickers2
  end

  def goes_long?
    #(redis.hget pk, "goes_long") == yes
    false
  end

  def goes_short?
    #(redis.hget pk, "goes_short") == yes
    false
  end

  def buy?(sec_id)
    false
  end

  def sell?(sec_id)
    false
  end

  def tag
    "entry_strategy:#{whoami[/EntryStrategy(.*)/,1]}" + "," + "setup_src:systematic"
  end

  def config_buy_entry(setup)
    sec_id, ticker = parse_setup(setup)
    { ticker:             sec_master.stock_tkr(sec_id),
      sec_id:             sec_id,
      entry_signal:       "systematic",
      trade_type:         "Position",
      side:               "long",
      setup_src:          name,
      trailing_stop_type: "atr",
      tags:               tag,
    }
  end

  def config_sell_entry(sec_id)
    { ticker:             sec_master.stock_tkr(sec_id),
      sec_id:             sec_id,
      entry_signal:       "systematic",
      trade_type:         "Position",
      side:               "short",
      setup_src:          name,
      trailing_stop_type: "atr",
      tags:               tag,
    }
  end

  def parse_setup(setup)
    sec_id, ticker = setup.split(":")
    [sec_id, ticker]
  end

  ##############
  private
  ##############
 
  def pk
    redis_name ||= name.gsub("_",":")
    "systematic:#{redis_name}"
  end
end
