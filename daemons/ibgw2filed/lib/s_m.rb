#require "my_config"
require "zts_constants"
require "store_mixin"
require "s_n"
require "log_helper"
require "singleton"

class SM
  include ZtsConstants
  include Store
  include LogHelper
  include Singleton
  
  attr_reader :sequencer

  def initialize
    #show_info "SM#initialize"
    @sequencer = SN.instance
  end
  
  def insert_update(mkt,sec_id,rec)
    rec.keys.each do |k|
      redis_md.hset "lvc:#{mkt}:#{sec_id}", k.to_sym, rec[k]
    end
    sec_id
  end

  def stock_tkr(sec_id)
    redis_md.hget "sec:#{sec_id}", 'tkr'
  end
  
  def ib_tkr(sec_id)
    redis_md.hget "sec:#{sec_id}", 'ib_tkr'
  end
  
  def sec_lookup(tkr)
    #puts "redis_md.get tkrs:#{tkr}"
    redis_md.get "tkrs:#{tkr}"
  end

  def index_lookup(tkr)
    redis_md.get "tkrs:#{tkr}"
  end

  TkrLables = {stock: "tkrs", index: "itkrs"}
  def tkr_lookup(mkt, tkr)
    redis_md.get "#{TkrLables[mkt.to_sym]}:#{tkr}"
  end
  
  def decode_ticker(ticker_id)
    #[MarketsIndex[ticker_id.to_i/TkrDivisor], ticker_id.to_i%TkrDivisor]
    ["stock", ticker_id]
  end

  def encode_ticker(market, id)
    #Markets[market.to_sym].to_i*TkrDivisor + id.to_i
    id.to_i
  end 

  def indics(mkt, id)
    pre = (mkt == "stock" ? "sec" : "index")
    redis_md.hgetall "#{mkt}:#{id}"
  end

  def indics_by_tkr(mkt, tkr)
    id = tkr_lookup(mkt, tkr)
    indics(mkt, id)
  end
  
  def stock_indics(id)
    redis_md.hgetall "sec:#{id}"
  end

  def index_indics(id)
    redis_md.hgetall "index:#{id}"
  end
  
  def atr(sec_id)
    ((redis_md.hget "lvc:stock:#{sec_id}", "atr14d") || 0).to_f
  end

  def last(sec_id)
    # tbd
    (redis_md.hget "lvc:stock:#{sec_id}", "close").to_f
  end

  def open(sec_id)
    # tbd
    (redis_md.hget "lvc:stock:#{sec_id}", "open").to_f
  end

  def high(sec_id)
    # tbd
    (redis_md.hget "lvc:stock:#{sec_id}", "high").to_f
  end

  def low(sec_id)
    # tbd
    (redis_md.hget "lvc:stock:#{sec_id}", "low").to_f
  end

  def wap(sec_id)
    # tbd
    #puts "redis_md.hget \"lvc:stock:#{sec_id}\", \"wap\""
    (redis_md.hget "lvc:stock:#{sec_id}", "wap").to_f
  end
  
  ###############
  private
  ###############

end
