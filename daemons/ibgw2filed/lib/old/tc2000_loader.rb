#!/usr/bin/env ruby

require_relative "mystdlib/tc_data"
require_relative "setup_mgr"
require_relative "file_helper"
require "monkey_patch/enumerable_patch"
require "db_data_queue/producer"
require "log_helper"

DataDir = "/Users/szagar/zts/data/inbox/setups/tc2000"
EntrySignals = { "ew" =>  "engulfing-white",
                 "pb" =>  "pre-buy",
                 "sb" =>  "springboard",
                 "d"  =>  "dragon",
               }
TradeType    = { "p" =>  "Position",
                 "s" =>  "Swing",
               }

class Tc200Loader
  include FileHelper
  include LogHelper

  attr_reader :ticker, :setup_mgr, :tc

  def initialize
    @setup_mgr = SetupMgr.new
    @tc = TcData.new
  end

  def generate_setups(search_str="#{DataDir}/**/*.txt")
    setups = Array.new
    puts "Look for TC files in ... #{search_str}"
    Dir.glob(search_str).sort_by{|f| File.mtime(f)}.each do |raw_fn|
      puts "process TC file: #{raw_fn}"
      working_dir = File.dirname(raw_fn).sub("inbox","archive")
      puts "working_dir=#{working_dir}"
      system 'mkdir', '-p', working_dir
      fn = archive_file(working_dir, raw_fn)
      puts "working file name is #{fn}"

#      load_sec_data(fn)
      #tc = TcData.new(fn)
      tc.load_file(fn)

      params = parse_filename(raw_fn)
puts "params 1 : #{params}"
      params = update_params(params)
puts "params 2 : #{params}"
      #setup = config_setup(parse_filename(raw_fn))
      setup = config_setup(params)

      transcript = StringIO.new
      unless setup.valid?(transcript)
        warn "Setup NOT Valid!!"   #  : #{setup}"
        warn transcript.string
        next
      end

      show_info "Setup Valid"
  
      setup.tags += tags_of_interest(tc)
      show_info "tags for #{setup.setup_id}: #{setup.tags}"
      tc.show_columns
      tc.data_dump(10)
      tc.csv(10).each { |r| puts r }
      puts "prev low            = #{tc.prev("low")}"
      puts "prev high           = #{tc.prev("high")}"
      puts "prev close          = #{tc.prev("close")}"
      puts "last low            = #{tc.last("low")}"
      puts "last high           = #{tc.last("high")}"
      puts "last close          = #{tc.last("close")}"
      puts "34 period low ema   = #{tc.ema('low',34)}"
      puts "34 period close ema = #{tc.ema('close',34)}"
      puts "34 period high ema  = #{tc.ema('high',34)}"
      puts "10 period close sma/ema           = #{tc.sma('close',10)} / #{tc.ema('close',10)}"
      puts "10 period volume sma/ema          = #{tc.sma('volume',10)} / #{tc.ema('volume',10)}"
      puts "10 period balance_of_power sma/ema= #{tc.sma('balance_of_power',10)} / #{tc.ema('balance_of_power',10)}"
      puts "10 period tsv_24 sma/ema          = #{tc.sma('tsv_24',10)} / #{tc.ema('tsv_24',10)}"
      setups << setup
    end
    setups
  end

  def run
    setups = generate_setups
    puts "Tc200Loader#run setups=#{setups}"
#    puts "setup env for test"
#    setup_mgr.config_env("test")
#    setup_mgr.run(setups)
#    puts "setup env for production"
#    setup_mgr.config_env("production")
#    setup_mgr.run(setups)

#    setup_mgr.run(setups)
    setup_mgr.submit_paper(setups)
    setup_mgr.submit_broker(setups) if ENV['ZTS_ENV'] == "production"
  end

  def config_setup(meta)
puts "meta=#{meta}"
    puts "setup_mgr.config_setup(#{meta})"
    setup_mgr.config_setup(meta)
  rescue
    NullSetup.new
  end
 
  private

  def update_params(params)
    puts "update_params(#{params})"
    params[:trailing_stop_type] ||= "atr"
    params[:entry_stop_price] ||= calc_entry_stop_from_tc
    params
  end

  def tags_of_interest(tc)
    debug "Tc2000Loader#tags_of_interest"
    tags = ""
    debug "0 : #{tags}"
    tags += "charts"
    debug "1 : #{tags}"
    (tags += "," + format_tag("bop", tc.last("balance_of_power").round(0))) rescue nil
    debug "2 : #{tags}"
    (tags += "," + format_tag("trend_dir", trend_dir(tc))) rescue nil
    debug "3 : #{tags}"
    (tags += "," + format_tag("bop_rank", tc.series("balance_of_power").reverse.rank.round(2))) rescue nil
    debug "4 : #{tags}"
    (tags += "," + format_tag("bop_5d_rank", tc.series("balance_of_power",5).reverse.rank.round(2))) rescue nil
    debug "5 : #{tags}"
    tags += "," + format_tag("rsi_signal1") if rsi_signal1?(tc)
    debug "6 : #{tags}"
    tags += "," + format_tag("rsi_signal2") if rsi_signal2?(tc)
    debug "7 : #{tags}"
    tags += "," + format_tag("NH10p")       if tc.series("close").reverse.rank >= 0.90
    debug "8 : #{tags}"
    tags += "," + format_tag("NH5p")        if tc.series("close").reverse.rank >= 0.95
    debug "9 : #{tags}"
    tags += "," + format_tag("NH6m10p")     if tc.series("close",125).reverse.rank >= 0.90
    debug "10 : #{tags}"
    tags += "," + format_tag("NH6m5p")      if tc.series("close",125).reverse.rank >= 0.95
    debug "11 : #{tags}"
    tags += "," + format_tag("volsig1")     if volume_signal1?(tc)
    debug "12 : #{tags}"
    tags += "," + format_tag("bopsig1")     if bop_signal1?(tc)
    debug "13 : #{tags}"
    tags += "," + format_tag("trendsig1")   if trend_signal1?(tc)
    debug "14 : #{tags}"
    tags
  end

  def format_tag(name,value=nil)
    value ? "#{name}:#{value}" : name
  end

  def load_sec_data(fn)
    tc_data = TcData.new(fn)
    sec_id = sec_master.insert_update("stock",sec_master.sec_lookup(data[:ticker]),data)
    db_queue.push(DbDataQueue::Message.new(command: "sec_data",
                  data: {sec_id: sec_id, ticker: ticker,
                         ema34_high: tc_data.ema('high',34),
                         ema34_low:  tc_data.ema('low',34)
                        }))
  end

  def parse_filename(fn)
    #BAS-b-ew-s22.65.txt
    #BAS-b-ew-s=22.65
    #/Users/szagar/zts/data/inbox/setups/tc2000/TT_swing_trade_momentum/engulfing_white/CBG.txt

    params = Hash.new

    params[:setup_src] = "worden"

    #subd = fn.split('/')[-2]
    fn.split('/').each do |subd|
      case subd
      when /TT_/
        params[:setup_src]    = subd
      when "investments","swing_trades","intraday_trades"
        params[:setup_src]    = subd
      end
    end

    fn.split('/').each do |subd|
puts "subd=#{subd}"
      case subd
      when /swing/
        params[:trade_type]   = "Swing"
      when /position/
        params[:trade_type]   = "Position"
      when /martha/
        params[:entry_signal] = EntrySignals["pb"]
        params[:action]       = "buy"
      when "engulfing-white","engulfing_white"
        params[:entry_signal] = EntrySignals["ew"]
        params[:action]       = "buy"
        params[:trade_type]   = TradeType["s"]
      when "dragon"
        params[:entry_signal] = EntrySignals["d"]
        params[:action]       = "buy"
        params[:trade_type]   = TradeType["s"]
      when "pre-buy"
        params[:entry_signal] = EntrySignals["pb"]
        params[:action]       = "buy"
        params[:trade_type]   = TradeType["s"]
      when "springboard"
        params[:entry_signal] = EntrySignals["sb"]
        params[:action]       = "buy"
        params[:trade_type]   = TradeType["s"]
      end
    end
    attributes = File.basename(fn,".txt").split '-'
    @ticker = attributes.shift
    params[:ticker] = ticker
    attributes.each do |attr|
      parm, val = attr.split("=")
      case parm
      when 'b','s'
        params[:action] = (parm == "b" ? "buy" : "sell")
      when 'es'
        puts "params[:entry_signal] = EntrySignals[#{val}]"
        params[:entry_signal] = EntrySignals[val]
      when "spt"
        params[:support] = val.to_f
        params[:trailing_stop_type] = "support"
      when "tt"
        puts "params[:trade_type] = TradeType[#{val}]"
        params[:trade_type] = TradeType[val]
      when "stp"
        puts "params[:entry_stop_price] = #{val.to_f}"
        params[:entry_stop_price] = val.to_f
      when "pts"
        params[:avg_run_pt_gain] = params[:tgt_gain_pts]  = val.to_f
      else
        params[:tags] += "," +  (val ? "#{parm}:#{val}" : "#{parm}")
      end
    end
    puts "params=#{params}"
    params
  end

  private
  
  def calc_entry_stop_from_tc
    work_price = tc.last('close') 
    work_price + ((work_price < 10) ? 0.12 : 0.25)
  end

  def trend_dir(tc)
    trend =  tc.last("lin_reg_25") / tc.prev("lin_reg_25",24)
    return "-" unless trend > 0.15
    trend > 0.0 ? "+" : "-"
  end

  def trend_signal1?(tc)
    ( tc.last("lin_reg_25") / tc.prev("lin_reg_25",24) ) > ( tc.last("lin_reg_75") / tc.prev("lin_reg_75",74) )
  end

  def volume_signal1?(tc)
    tc.last("volume") > tc.last("volume_exp_moving_average_25")
  end

  def bop_signal1?(tc)
    tc.last("balance_of_power") > 0  &&
    tc.last("balance_of_power") > tc.prev("balance_of_power")
  end

  def rsi_signal1?(tc)
    tc.last("wilders_rsi_15") > tc.last("wilders_rsi_75") &&
    tc.last("wilders_rsi_15") > tc.prev("wilders_rsi_15")
  end
  
  def rsi_signal2?(tc)
    tc.last("wilders_rsi_15") > tc.last("wilders_rsi_75") &&
    tc.last("wilders_rsi_15") > tc.prev("wilders_rsi_15") &&
    tc.prev("wilders_rsi_15") > tc.prev("wilders_rsi_15",2)
  end
end

Tc200Loader.new.run

__END__

Date,Open,High,Low,Close,Wilder's RSI 15,Wilder's RSI 75,TSV 24,Exp Moving Average 12,Volume ,Exp Moving Average 25,Balance Of Power,MoneyStream ,Exp Moving Average 12
4/3/12 12:00:00 AM -04:00,17.95,18.25,17.71,17.99,,,,,1011200,,,0,
4/4/12 12:00:00 AM -04:00,17.7,17.91,17,17.03,,,,,1339400,,-13,-1.9489,
4/5/12 12:00:00 AM -04:00,16.9,17.02,16.45,16.64,,,,,1662500,,3,-3.0794,
