
module Tc2000EntryFilters

  def pre_buy?(tc,params)
    puts "Tc2000EntryFilters#pre_buy?=true"
    true
  end

  def descretionary?(tc,params)
    puts "Tc2000EntryFilters#descretionary?=true"
    true
  end

  def manual?(tc,params)
    puts "Tc2000EntryFilters#manual?"
    params[:setup_src][/manual/]
  end

  def engulfing_white?(tc,params)
    puts "Tc2000EntryFilters#engulfing_white?=#{tc.engulfing_white?}"
    tc.engulfing_white?
  end

  def long_bop1?(tc,params)
    entry_filter = params[:side] == "long" &&
                   bop_signal1?(tc) 
    puts "Tc2000EntryFilters#long_bop1?=#{entry_filter}"
    entry_filter
  end

  def long_bop1_rsi1?(tc,params)
    entry_filter = params[:side] == "long" &&
                   bop_signal1?(tc)        &&
                   rsi_signal2?(tc)
    puts "Tc2000EntryFilters#long_bop1_rsi1?=#{entry_filter}"
    entry_filter
  end

  def bop1_rsi2?(tc,params)
    entry_filter = false
    entry_filter = bop_signal1?(tc) && rsi_signal2?(tc) if params[:side] == "long"
    entry_filter = !bop_signal1?(tc) && !rsi_signal2?(tc) if params[:side] == "short"
    puts "Tc2000EntryFilters#bop1_rsi2?=#{entry_filter}"
    entry_filter
  end


  def bop1_rsi1?(tc,params)
    entry_filter = false
    entry_filter = bop_signal1?(tc) && rsi_signal1?(tc) if params[:side] == "long"
    entry_filter = !bop_signal1?(tc) && !rsi_signal1?(tc) if params[:side] == "short"
    puts "Tc2000EntryFilters#bop1_rsi1?=#{entry_filter}"
    entry_filter
  end
end
