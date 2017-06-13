#!/usr/bin/env ruby
# encoding: utf-8

# raw tc data:
# Date,Open,High,Low,Close,Exp Moving Average of Low 34,Exp Moving Average of High 34,Exp Moving Average 200,Volume ,Exp Moving Average 25,Balance Of Power,Exp Moving Average 25
# 5/1/12 12:00:00 AM -04:00,584.9,596.76,581.23,582.13,,,,2.18084E+07,,,
# 5/2/12 12:00:00 AM -04:00,580.48,587.4,578.86,585.98,,,,1.52654E+07,,9,
# 5/3/12 12:00:00 AM -04:00,590.5,591.4,580.3,581.82,,,,1.39333E+07,,17,
#
# max_data_points - number of data points in complete/unfiltered data set
# data_points     - number of data points
# data_set        - hash of data, ascending order
# data_array      - array of data (hash)
# last_date       - must recent date with eod data
# system_asof - points to current date for system
#

require "date"
# $: << "#{ENV['ZTS_HOME']}/lib2"
$: << "#{ENV['ZTS_HOME']}/lib"
require "string_helper"
require "patterns_mixin"

class TcData
  include Patterns

  attr_accessor :columns, :columns_hash, :data_set, :data_array, :short_names

  def initialize(fn=nil)
    @data_set = Hash.new
    @data_array = Array.new
    @columns_hash = Hash.new
    @columns      = Array.new
    @short_names  = Hash.new
    @emx_x        = Hash.new
    initialized_short_names
    load_file(fn) if fn
  end

  def set_asof(asof)
    prev = @system_asof
    @system_asof = asof
    prev
  end

  def system_asof
    @system_asof
  end

  def show_columns
    columns.each_with_index { |c,i| printf "%5s : %s\n", i, c }
  end

  def exists?(col)
    columns_hash.has_key?(col)
  end

  def data_dump(no_recs=data_points)
    header = columns.clone
    header.each do |h|
      fmt_str, sfmt_str = lookup_format(h)
      cname = h
      printf sfmt_str, cname
    end
    printf "\n"
    dates(no_recs).each do |d|
      data = data_set[d]
      header.each.map do |h|
        data_point = (h == "date" ? date_to_int(data[h]) : data[h])
        fmt_str, sfmt_str = lookup_format(h)
        #data_point.is_a?(Numeric) ? printf(fmt_str, data_point) : printf(sfmt_str, "")
        printf(sfmt_str, data_point)
      end
      printf "\n"
    end
  end

  def csv(no_recs=data_points)
    rec = Array.new
    results = Array.new
    header = columns.dup
    header.each do |h|
      #nick_name_patterns.each { |k,v| h.sub!(k,v) if h.match(k) }
      rec << h
    end
    results << rec.join(',')
    header = columns.clone
    dates(no_recs).each do |d|
      rec = Array.new
      data = data_set[d]
      header.each do |h|
        data_point = (h == "date" ? date_to_int(data[h]) : data[h])
        rec << (!!data_point ? data_point : "")
      end
      results << rec.join(',')
    end
results
  end

  def price_history(no_recs=data_points)
    dates(no_recs).map do |d|
      data = data_set[d]
      [d, data['open'], data['high'], data['low'], data['close']].join(',')
    end
  end

  def last_date
    ds = dates(1).first
  end

  def data_points
    dates.size
  end

  def max_data_points
    #data_set.size
    data_set.keys.sort.select {|d| d<= @system_asof}.size
  end

  def highest(field,periods=250)
    (dates(periods).map { |dt| data_set[dt][field].to_f }).max
  end

  def lowest(field,periods=250)
    (dates(periods).map { |dt| data_set[dt][field].to_f }).min
  end

  def high(periods=250)
    (dates(periods).map { |dt| data_set[dt]['close'].to_f }).max
  end

  def high_close(periods=250)
    (dates(periods).map { |dt| data_set[dt]['close'].to_f }).max
  end

  def dates(no_recs=max_data_points,desc=true)
    dates_asof = data_set.keys.sort.select {|d| d<= @system_asof}
    raise "Not enough date records: #{dates_asof.size} vs #{no_recs}" if dates_asof.size < no_recs
    desc ? dates_asof.last(no_recs).reverse
         : dates_asof.first(no_recs)
  end

  def series(field,periods=data_points)
    #raise unless columns.include?(field)
    dates(periods).map { |dt| data_set[dt][field].to_f }
  rescue
    []
  end

  def ohlc_history(periods=data_points)
    #dates(periods,false).map do |dt| 
    dates(periods).map do |dt| 
      rec = {date:  dt,
       open:  data_set[dt]["open"].to_f,
       high:  data_set[dt]["high"].to_f,
       low:   data_set[dt]["low"].to_f,
       close: data_set[dt]["close"].to_f,
      }
      rec
    end
  end

  def rets(field,periods=data_points)
    series(field,periods).each_cons(2).map { |curr,prev|
      #((curr.to_f-prev.to_f) / prev.to_f * 100.to_f).round(4)
      Math.log(curr.to_f/prev.to_f,2.7).round(4)*100
    }
  end

  def ohlc
    dt = dates(1)[0]
    rec = {date:  dt,
           open:  data_set[dt]["open"].to_f,
           high:  data_set[dt]["high"].to_f,
           low:   data_set[dt]["low"].to_f,
           close: data_set[dt]["close"].to_f,
    }
    rec
  end

  def last(field="close")
    data_set[dates(1)[0]][field].to_f
  end

  def prev(field,ago=1)
    data_set[dates(ago+1)[ago]][field].to_f
  end

=begin
  ## Patterns
  ##############
  def engulfing_white?(ago=0)
    pmax = [prev("close",ago+1), prev("open",ago+1) ].max
    pmin = [prev("close",ago+1), prev("open",ago+1) ].min
    white_candle? &&
    ( prev("close",ago) > pmax ) &&
    ( prev("open",ago) < pmin )
  end

  def white_candle?(ago=0)
    prev("close",ago) > prev("open",ago)
  end

  def black_candle?(ago=0)
    prev("close",ago) < prev("open",ago)
  end
=end

  def date(days_back=0)
    dates(days_back+1).last
  end

  def sma(field,periods)
    dates(periods).inject(0) { |sum,dt| sum += data_set[dt][field].to_f } / periods
  end
 
  def ema(field,periods)
    sum = 0.0
    ma  = 0.0
    factor = 2.0 / (1 + periods)
    dates(data_points,false).each_with_index do |dt,cnt|
      sum += data_set[dt][field].to_f if cnt < periods
      ma = sum / periods if cnt == periods
      #ma = ma * 0.90 + data_set[dt][field].to_f * 0.10 if cnt > periods
      #ma = (data_set[dt][field].to_f - ma) * factor + ma
      ma = calc_ema(periods, ma, data_set[dt][field].to_f) if cnt > periods
    end
    ma
  end
 
  def method_missing(method_name, *arguments, &block)
    if columns.include?(method_name.to_s)
      data_set[dates(1)[0]][method_name.to_s].to_f
      #puts "data_set[#{dates(1)[0]}].send(#{$1}, *arguments, &block)"
      #data_set[dates(1)[0]].send($1, *arguments, &block)
      #user.send($1, *arguments, &block)
    else
      puts "method_missing, column: #{method_name} not known"
      raise
      #super
    end
  rescue
    warn "unknown request: #{method_name.to_s}"
    []
  end

  def load_file(fn)
    @filename = fn
    open(fn) do |fh|
      load_header(fh.readline)
      load_data(fh)
    end
    @system_asof = data_set.keys.max
  end

#The ATR at the moment of time t is calculated using the following formula:[5]
#    ATR_t = [ATR(t-1}) / (n-1) + TR] / n
#The first ATR value is calculated using the arithmetic mean formula:
#
#    ATR = {1 \over n} \sum_{i=1}^n TR_i

  
  def set_tr
    col = "tr"
    return if exists?(col)
    set_prev_close
    add_column(col)
    dates.map { |dt| data_set[dt]['tr'] = tr(data_set[dt]) }
  end

  def set_rsi(period=14)
    col = "rsi_#{period}"
    return if exists?(col)
    set_delta
    add_column(col)

    gain_array = []
    loss_array = []
    work_dates = dates(period+1,false)
    work_dates.shift
    work_dates.each do |dt|
      delta = data_set[dt]["delta_close"] 
      gain_array << (delta > 0 ? delta : 0)
      loss_array << (delta < 0 ? delta.abs : 0)
    end
    #avg_gain = simple_avg_ah("day_gain",price_array).round(4)
    #avg_loss = simple_avg_ah("day_loss",price_array).round(4)
    avg_gain = gain_array.reduce(0,:+)/gain_array.size
    avg_loss = loss_array.reduce(0,:+)/loss_array.size
    rsi = calc_rsi(avg_gain,avg_loss)
    data_set[dates(period).last][col] = rsi

    # use exponential moving average for remaing dates
    work_dates = dates(max_data_points,false)
    work_dates.shift(period)
    work_dates.each do |dt|
      delta = data_set[dt]["delta_close"]
      avg_gain = calc_ema(period, avg_gain, [delta,0].max)
      avg_loss = calc_ema(period, avg_loss, [delta,0].min.abs)
      rsi = calc_rsi(avg_gain,avg_loss)
      #printf "avg_gain %4.1f  avg_loss %4.1f  rsi %4.1f\n",avg_gain,avg_loss,rsi
      data_set[dt][col] = rsi
    end
  end

  def calc_rsi(avg_gain,avg_loss)
    rs = avg_gain / avg_loss
    rsi = (100 - (100.0 / (1 + rs))).round(4)
  end

  def set_atr(period)
    col = "atr#{period}"
    return if exists?(col)
    set_prev_close
    set_tr
    add_column(col)

    # use simple avg for initial atr calc
    #dates(period,false).map { |dt| puts "date :: #{dt}  #{data_set[dt]['tr']}" }
    price_array = dates(period,false).map { |dt| data_set[dt] }
    atr = simple_avg_ah("tr",price_array).round(2)
    #puts "data_set[#{dates(period,false).last}][#{col}] = #{atr}"
    data_set[dates(period,false).last][col] = atr

    # use exponential moving average for remaing dates
    work_dates = dates(max_data_points,false)
    work_dates.shift(period)
    work_dates.each do |dt|
      atr = calc_ema(period, atr, data_set[dt]["tr"])
      #puts "data_set[#{dt}][#{col}] = #{atr}"
      data_set[dt][col] = atr.round(2)
    end
  end

  def atr_history(no_recs=max_data_points)
    #data_array.map { |d| d['atr'] }
    dates(no_recs).map { |d| data_set[d]['atr14'] }
  end
 
  def set_delta(field="close")
    #puts "set_delta(#{field})"
    col = "delta_#{field}"
    return if exists?(col)
    add_column(col)
    dates.each_cons(2).each { |curr,prev|
      data_set[curr][col] = (data_set[curr][field].to_f -
                             data_set[prev][field].to_f).round(2)
    }
  end

=begin
# redundant, same as delta
  # momentum pinball: Street Smarts, page 51
  def lbr(no_recs=data_points,field="close")
    dates(no_recs).each_cons(2).map do |curr,prev|
      (data_set[curr][field].to_f - data_set[prev][field].to_f).round(2)
    end
  end
=end

  def consecutive_down_days(field="close")
    cnt = 0
    dates(max_data_points).each_cons(2).each do |curr,prev|
      #puts "consecutive_down_days: #{data_set[curr][field]} < #{data_set[prev][field]}"
      break unless data_set[curr][field] < data_set[prev][field]
      cnt += 1
    end
    cnt
  end
# smz
  #def atr_history
  #  data_array.map { |d| d['atr'] }
  #end

  def atrp
    (last('atr14') / last('close') * 100.0).round(2)
  end

  def atrp_history(no_recs=max_data_points-14)
    #data_array.map { |d| (d['atr']/d['close'].to_f * 100.0).round(2) }
    dates(no_recs,true).map { |d| 
#puts "d=#{d}"
#puts "data_set[#{d}]=#{data_set[d]}"
#puts "data_set[#{d}][close]=#{data_set[d]['close']}"
#puts "data_set[#{d}][atr14]=#{data_set[d]['atr14']}"

(data_set[d]['atr14']/data_set[d]['close'].to_f * 100.0).round(2) }
  end

=begin
  def trend_dir(tc)
    trend =  tc.last("lin_reg_25") / tc.prev("lin_reg_25",23)
    return "-" unless trend > 0.015
    trend > 0.0 ? "+" : "-"
  end

  def trend_signal1?(tc)
    ( tc.last("lin_reg_25") / tc.prev("lin_reg_25",23) ) > ( tc.last("lin_reg_75") / tc.prev("lin_reg_75",73) )
  end

  def volume_signal1?(tc)
    #puts "tc.last(volume)                       = #{tc.last('volume')}"
    #puts "tc.last(volume_exp_moving_average_25) = #{tc.last('volume_exp_moving_average_25')}"
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
    tc.last("wilders_rsi_15") > tc.last("wilders_rsi_75") &&
    tc.last("wilders_rsi_15") > tc.prev("wilders_rsi_15") &&
    tc.prev("wilders_rsi_15") > tc.prev("wilders_rsi_15",2)
  end
=end
  ###########
  private
  ###########

  def eod_data_only?
    true
  end

  def eod_data(date_str)
    @tc_time_fmt ||= "%m/%d/%y %H:%M:%S %p"
    (date_str.match(/ 12:00:00 AM/) || DateTime.strptime(date_str,@tc_time_fmt).hour > 16)
  end

  def calc_ema(periods, curr_ema, value)
    #((curr_ema * (periods-1) + value) / periods).round(4)
    @emx_x[periods] || @emx_x[periods] = 2.0 / (periods+1) 
    (value - curr_ema) * @emx_x[periods] + curr_ema
  end

  def simple_avg_ah(field,array_of_hash)
    array_of_hash.map { |d| d[field]}.reduce(0,:+)/array_of_hash.size
  end

  def tr(prices)
    [ (prices['high'].to_f-prices['low'].to_f),
      (prices['prev_close'].to_f-prices['low'].to_f).abs,
      (prices['prev_close'].to_f-prices['high'].to_f).abs].max.round(4)
  end
 
  def set_prev_close
    col = "prev_close"
    return if exists?(col)
    add_column(col)

    all_dates = dates(max_data_points,false)
    earliest_date = all_dates.shift
    prev_close = data_set[earliest_date]['close']
    data_set[earliest_date][col] = prev_close
    all_dates.each do |d|
      data = data_set[d]
      data[col] = prev_close
      prev_close = data['close']
    end
  end

  def load_header(rec)
    @columns    = []
    @columns_hash = {}
puts "rec=#{rec}"
    cols = rec.split(",").map { |c| c.strip.gsub("'","").gsub(/ +/,"_").downcase }
    @columns = cols.map.with_index do |c,i|
      @icol = (c.include?("moving_average")) ? @icol + 1 : 0 
      (c.include?("moving_average")) ?  c.prepend(cols[i-@icol]+"_") : c 
    end
    columns.each_with_index { |c,i| @columns_hash[c] = i }
  end

  def add_column(name)
    @columns << name
    @columns_hash[name] = @columns.size
  end

  def load_data(fh)
    @data_set   = {}
    @data_array = []
    fh.each do |line|
      day_array = line.split(",")
      next if (eod_data_only? &&
               !eod_data(day_array[columns_hash["date"]]))
      date = date_to_int(day_array[columns_hash["date"]])
      day_hash = array2hash(day_array)
      @data_set[date] = day_hash
      @data_array << day_hash
    end
  end

  def date_to_int(date)
    #unless date =~ /^(1[0-2]|0?[1-9])/(3[01]|[12][0-9]|0?[1-9])/(?:[0-9]{2})?[0-9]{2}$/
    date =~ /^(\d+)\/(\d+)\/(\d+)/
   # unless (date =~ /^[/(\d+)\/(\d+)\/(\d+)$/)
   #   warn "Not in expected date format(m/d/yy): #{date}" unless date ~= /\d
   #   return "?"
   # end
    month, day, year = $1.to_i, $2.to_i, $3.to_i
    year += 2000 if year < 100
    year*10000 + month*100 + day
  end

  def array2hash(day_array)
    data_hash = {}
    day_array.each_with_index do |d,i|
      data_hash[columns[i]] = d.chomp
    end
    data_hash
  end

  def nick_name_patterns
    { 'wilders_rsi'         =>  'rsi15',
      'exp_moving_average'  =>  'ema',
      'volume'              =>  'vol',
      'balance_of_power'    =>  'bop',
      'moneystream'         =>  'ms',
    }
  end

  def initialized_short_names
    @short_names['wilders_rsi_15']                    = 'rsi-15'
    @short_names['wilders_rsi_75']                    = 'rsi-75'
    @short_names['tsv_24']                            = 'tsv2-4'
    @short_names['tsv_24_exp_moving_average_12']      = 'tsv-ema'
    @short_names['volume']                            = 'vol'
    @short_names['volume_exp_moving_average_25']      = 'vol-ema'
    @short_names['balance_of_power']                  = 'bop'
    @short_names['moneystream']                       = 'ms'
    @short_names['moneystream_exp_moving_average_12'] = 'ms-ema'
  end

  def lookup_format(col)
    case col
    when "date"
      ["%8s", "%8s"]
    when /volume/
      ["%10.0f", "%10s"]
    when /wilder/
      ["%8.2f", "%8s"]
    when /balance_of_power/
      ["%6.2f", "%6s"]
    when /moneystream/
      ["%8.2f", "%8s"]
    when /tsv/
      ["%10.2f", "%10s"]
    else
      ["%6.2f", "%6s"]
    end
  end

end

