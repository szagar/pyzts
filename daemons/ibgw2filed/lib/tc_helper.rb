require_relative "tags"
#require_relative "file_helper"
#require_relative "tc_helper"

EntrySignals = { "ew" =>  "engulfing-white",
                 "pb" =>  "pre-buy",
                 "sb" =>  "springboard",
                 "d"  =>  "dragon",
               }
TradeType    = { "p" =>  "Position",
                 "s" =>  "Swing",
               }

module TcHelper
  def tags_of_interest(tc, tags = Tags.new)
    tags.add_tag("bbw_12_2",         tc.last("bollinger_bandwidth_12_2").round(2))
    tags.add_tag("bop",         tc.last("balance_of_power").round(0))
    tags.add_tag("trend_dir",   trend_dir(tc))
    tags.add_tag("bop_rank",    tc.series("balance_of_power").rank.round(2))
    tags.add_tag("bop_5d_rank", tc.series("balance_of_power",5).rank.round(2))

    tags.add_tag("sqn_5",   tc.rets("close",5).system_quality_number.round(2))
    tags.add_tag("sqn_25",  tc.rets("close",25).system_quality_number.round(2))
    tags.add_tag("sqn_50",  tc.rets("close",50).system_quality_number.round(2))
    tags.add_tag("sqn_100", tc.rets("close",100).system_quality_number.round(2))
    tags.add_tag("sqn_200", tc.rets("close",200).system_quality_number.round(2))

    tags.add_tag("NH10p")       if tc.series("close").reverse.rank >= 0.90
    tags.add_tag("NH5p")        if tc.series("close").reverse.rank >= 0.95
    tags.add_tag("NH6m10p")     if tc.series("close",125).reverse.rank >= 0.90
    tags.add_tag("NH6m5p")      if tc.series("close",125).reverse.rank >= 0.95

    ## Signals
    tags.add_tag("volume_signal1")  if volume_signal1?(tc)
    tags.add_tag("bop_signal1")     if bop_signal1?(tc)
    tags.add_tag("trend_signal1")   if trend_signal1?(tc)
    tags.add_tag("rsi_signal1")     if rsi_signal1?(tc)
    tags.add_tag("rsi_signal2")     if rsi_signal2?(tc)

    ## Patterns
    tags.add_tag("nesting_white")   if tc.nesting_white?
    tags.add_tag("engulfing_white") if tc.engulfing_white?
    tags.add_tag("engulfing_black") if tc.engulfing_black?
    tags.add_tag("white_candle")    if tc.white_candle?
    tags.add_tag("black_candle")    if tc.black_candle?
    tags.add_tag("pattern_1")       if tc.pattern_1?
    tags
  end

  def format_tag(name,value=nil)
    value ? "#{name}:#{value}" : name
  end

  def parse_filename(fn)

    params = Hash.new

    subdirs = fn.split('/')
    params[:setup_src] = subdirs[-2]
    subdirs.each do |subd|
      case subd
      when /BiR/
        params[:setup_src]    = subd
      when /Worden/
        params[:setup_src]    = subd
      when /TT-Scan-Swing/
        params[:setup_src]    = subd
      when "investments","swing_trades","intraday_trades"
        params[:setup_src]    = subd
      end
    end

    fn.split('/').each do |subd|
      case subd
      when /swing/
        params[:trade_type]   = "Swing"
      when /position/
        params[:trade_type]   = "Position"
      when /martha/
        params[:entry_signal] = EntrySignals["pb"]
        params[:side]       ||= "long"
      when "engulfing-white","engulfing_white"
        params[:entry_signal] = EntrySignals["ew"]
        params[:side]       ||= "long"
        params[:trade_type] ||= TradeType["s"]
      when "dragon"
        params[:entry_signal] = EntrySignals["d"]
        params[:side]       ||= "long"
        params[:trade_type] ||= TradeType["s"]
      when "pre-buy"
        params[:entry_signal] = EntrySignals["pb"]
        params[:side]       ||= "long"
        params[:trade_type] ||= TradeType["s"]
      when "springboard"
        params[:entry_signal] = EntrySignals["sb"]
        params[:side]       ||= "long"
        params[:trade_type] ||= TradeType["s"]
      end
    end
    attributes = File.basename(fn,".txt").split '-'
    params[:ticker] = attributes.shift
    attributes.each do |attr|
      parm, val = attr.split("=")
      case parm
      when 'b','s'
        params[:side] = (parm == "b" ? "long" : "short")
      when 'es'
        params[:entry_signal] = EntrySignals[val]
      when "spt"
        params[:support] = val.to_f
        params[:trailing_stop_type] = "support"
      when "tt"
        params[:trade_type] = TradeType[val]
      when "pid"
        params[:pos_id] = val.to_i
      when "stp"
        params[:entry_stop_price] = val.to_f
      when "pts"
        params[:avg_run_pt_gain] = params[:tgt_gain_pts]  = val.to_f
      when "init"
        params[:take_init_pos] = true
      when "add"
        params[:pyramid_pos] = true
      when "gtc"
        params[:gtc] = true
      when "des"
        params[:descretionary] = true
      else
        params[:tags] ||= Tags.new
        params[:tags].add_tag(parm,val)
      end
    end
    params
  end


  def trend_dir(tc)
    trend =  tc.last("lin_reg_25") / tc.prev("lin_reg_25",24)
    return "-" unless trend > 0.15
    trend > 0.0 ? "+" : "-"
  end

  def trend_signal1?(tc)
    ( tc.last("lin_reg_25") / tc.prev("lin_reg_25",24) ) > ( tc.last("lin_reg_75") / tc.prev("lin_reg_75",74) )
  rescue
    false
  end

  def volume_signal1?(tc)
    tc.last("volume") > tc.last("volume_exp_moving_average_25")
  end

  def bop_signal1?(tc)
    tc.last("balance_of_power") > 0  &&
    tc.last("balance_of_power") > tc.prev("balance_of_power")
  end

  def bop_signal2?(tc)
    orig_dt =  tc.set_asof(tc.dates(2).last)
    prev_bop_ema = tc.ema("balance_of_power",25)
    tc.set_asof(orig_dt)
    tc.last("balance_of_power") > 0  &&
    tc.last("balance_of_power") > tc.prev("balance_of_power") &&
    tc.last("balance_of_power") > prev_bop_ema
  end

  def rsi_signal1?(tc)
    tc.last("wilders_rsi_15") > tc.last("wilders_rsi_75") &&
    tc.last("wilders_rsi_15") > tc.prev("wilders_rsi_15")
  end

  def rsi_signal2?(tc)
    tc.last("wilders_rsi_15") >= tc.last("wilders_rsi_75") &&
    tc.last("wilders_rsi_15") >= tc.prev("wilders_rsi_15") &&
    tc.prev("wilders_rsi_15") >= tc.prev("wilders_rsi_15",2)
  end

  def calc_entry_stop_from_tc(side="long")
    work_price = (side == "short") ? @tc.last('low') : @tc.last('high')
    calc_entry_stop_price(side,work_price)
  end

  def calc_entry_stop_price(side,work_price)
    px_adj =  (work_price < 10) ? 0.12 : 0.25
    px_adj =  0.06 if work_price < 5.0
    (side == "short") ? work_price-px_adj : work_price+px_adj
  end

  def calc_limit_price_from_stop(side,stop_price)
    px_adj =  (stop_price < 10) ? 0.25 : 0.38
    px_adj =  0.12 if stop_price < 5.0
    ((side == "short") ? stop_price-px_adj : stop_price+px_adj).round(2)
  end
end
