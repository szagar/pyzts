require "stringio"
require "zts_constants"
require "misc_helper"
require "log_helper"

class NullSetup
  def valid?
    false
  end
end

include LogHelper

SetupStruct = Struct.new( :setup_id,        :ticker,            :sec_id,      :mkt,   :pos_id,
                          :setup_src,       :trade_type,        :side,        :tod,
                          :limit_price,     :entry_stop_price,  :trailing_stop_type,
                          :tif,             :entry_signal,      :entry_filter,
                          :weak_support,    :moderate_support,  :strong_support,
                          :setup_support,     :support,         :atr,
                          :avg_run_pt_gain, :tgt_gain_pts,
                          :swing_rr,        :position_rr,       :pyramid_pos,
                          :adjust_stop_trigger,                          
                          :daytrade_exit,   :rps_exit,
                          :triggered_entries, :pending_entries,         :status,
                          :mca_tkr,           :mca,
                          :notes, :tags
                           ) do
  def self.from_hash(attributes)
    instance = self.new
    attributes.each do |key, value|
      next unless self.members.include?(key.to_sym)
      instance[key] = value
    end
    instance
  end

  def attributes(fields=members)
    result = {}
    fields.each do |name|
      result[name] = self[name]
    end
    result
  end
  
  def to_human
    "#{setup_src}/#{trade_type}(#{setup_id}) #{ticker}(#{sec_id}) #{side} #{tod} tags=#{tags} #{notes}"
  end

  def valid?(transcript=StringIO.new)
    rtn = true

    rtn = false unless (ticker && ticker.size > 0)

    unless ZtsConstants::TradeType.include?(trade_type)
      transcript.puts "invalid trade_type: #{trade_type}"
      warn "invalid trade_type: #{trade_type}"
      rtn = false
    end

    if (trade_type   == "Swing"    &&
        !((avg_run_pt_gain.to_f  rescue 0)>0))
      transcript.puts "trade_type: #{trade_type}, #{avg_run_pt_gain}"
      warn "trade_type: #{trade_type}, #{avg_run_pt_gain}"
      rtn = false
    end
    if (trade_type   == "Swing"    &&
        !((avg_run_pt_gain.to_f  rescue 0)>0))
      transcript.puts "trade_type: #{trade_type}, #{avg_run_pt_gain}"
      warn "trade_type: #{trade_type}, #{avg_run_pt_gain}"
      rtn = false
    end
    if (trade_type   == "Position" &&
        !((tgt_gain_pts.to_f     rescue 0)>0))
      transcript.puts "trade_type: #{trade_type}, #{tgt_gain_pts}"
      warn "trade_type: #{trade_type}, #{tgt_gain_pts}"
      rtn = false
    end
    if (entry_signal == "pre-buy"  &&
        !((entry_stop_price.to_f rescue 0)>0))
      transcript.puts "trade_type: #{trade_type}, #{entry_stop_price}"
      warn "trade_type: #{trade_type}, #{entry_stop_price}"
      rtn = false
    end
    
    unless MiscHelper::valid_id?(sec_id.to_i)
      transcript.puts "Ticker:#{ticker} invalid sec_ids(#{sec_id})"
      warn "Ticker:#{ticker} invalid sec_ids(#{sec_id})"
      rtn = false
    end
    unless ZtsConstants::LongEntrySignals.include? entry_signal
      transcript.puts "invalid enty signal: #{entry_signal}"
      warn "invalid enty signal: #{entry_signal}"
      rtn = false
    end
    unless ZtsConstants::TrailingStops.include? trailing_stop_type
      transcript.puts "invalid trailing stop type: #{trailing_stop_type}"
      warn "invalid trailing stop type: #{trailing_stop_type}"
      rtn = false
    end

    case entry_signal
    when "pre-buy", "systematic"
      unless MiscHelper::valid_price?(entry_stop_price)
        transcript.puts "Ticker:#{ticker} #{entry_signal} setups require entry stop price(#{entry_stop_price})"
        warn "Ticker:#{ticker} #{entry_signal} setups require entry stop price(#{entry_stop_price})"
        rtn = false
      end
    end

    case trailing_stop_type
    when "ema"
      unless lvc.exists?("ema34_high", sec_id) && lvc.exists?("ema34_low", sec_id)
        transcript.puts "Ticker:#{ticker}/#{sec_id} ema stop loss require EMA H/L"
        warn "Ticker:#{ticker}/#{sec_id} ema stop loss require EMA H/L"
        rtn = false
      end
    when "atr"
    when "support"
      unless MiscHelper::valid_price?(support)
        transcript.puts "Ticker:#{ticker} #{trailing_stop_type} setups require support(#{support})"
        warn "Ticker:#{ticker} #{trailing_stop_type} setups require support(#{support})"
        rtn = false
      end
    end

    rtn = false if (false)
    rtn
  end

end
