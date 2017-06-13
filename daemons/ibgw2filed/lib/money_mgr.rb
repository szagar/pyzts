require "account_mgr"
require "trade"
require "last_value_cache"
require "zts_constants"
require "log_helper"
require "stringio"

class InvalidEntryError       < StandardError; end

class MoneyMgr
  include LogHelper
  include ZtsConstants

  def initialize
    @account_mgr = AccountMgr.new
    @lvc = LastValueCache.instance
  end

  # smz dev
  #def accounts
  # @account_mgr.accounts  #.collect { |account| account['status'] == "active" }
  #end

  def trades_for_entry(entry_id)
    show_info "MoneyMgr#trades_for_entry(#{entry_id})"
    entry = EntryProxy.new(entry_id: entry_id)
    show_info "MoneyMgr#trades_for_entry: entry.attributes=#{entry.dump}"
    entry.trailing_stop_type ||= account.trailing_stop_type
    trans = StringIO.new
    unless valid_entry?(entry, trans) 
      warn "trades_for_entry: entry NOT valid  entry=#{entry.dump}:: #{trans.string}" 
      raise InvalidEntryError, "trades_for_entry:  entry=#{entry.dump}:: #{trans.string}" 
    end
    if scaling_in?(entry) 
      trade_list = trade_for_open_position(entry)
    else
      trades_for_accounts(entry)
    end
    trade_list
  end

  def trade_for_open_position(entry)
    trade_list = []
  end

  def test_equity_model(model, account)
    self.send("#{model}_risk_dollars", account)
  end

  def init_risk_share(account, entry)
    debug "MoneyMgr#init_risk_share: trailing_stop_type = #{entry.trailing_stop_type}"
    sidex     = (entry.side == "long") ? 1 : -1
    stop_type = entry.trailing_stop_type
    debug "MoneyMgr#init_risk_share: stop_type = #{stop_type}"
    last_px   = @lvc.last(entry.sec_id).to_f

    case stop_type
    when "support"
      (last_px - (entry.support.to_f - sidex * ((last_px < 10.0) ? 0.12 : 0.25))).abs
    when "support_x"
      (last_px - entry.support.to_f).abs
    when "atr"
      show_info "MoneyMgr#init_risk_share: atr_factor         = #{account.atr_factor}"
      atr = entry.atr.to_f || @lvc.atr(entry.sec_id).to_f
      warn "atr for sec_id #{entry.sec_id} is not > 0" unless atr > 0
      (atr * account.atr_factor.to_f).round(4)
    when "ema"
      level = (entry.side == "long") ? "low" : "high"
      (last_px - @lvc.ema(entry.sec_id,level,34)).abs
    when "manual"
      (entry.side == "long") ? (entry.entry_stop_price - entry.stop_loss_price)
                             : (entry.stop_loss_price - entry.entry_stop_price)
    when "tightest"
      level = (entry.side == "long") ? "low" : "high"
      (last_px - @lvc.ema(entry.sec_id,level,34)).abs
    when "timed"
      last_px * 0.25
    else
      warn "Invalid trailing_stop_type: #{stop_type}"
      raise InvalidEntryError, "Invalid trailing_stop_typei: #{stop_type}"
    end
  end

  ################
  private
  ################


  def VanTharp_size(trade)
    (trade.init_risk_position / trade.init_risk_share).round(0)
  end

  def Martha_size(trade)
    shares = 1
    trade.init_risk_position = trade.init_risk_share * shares
    shares 
  end

  def valid_entry?(entry, transcript=StringIO.new)
    #puts " valid_entry?(#{entry.dump})"
    rtn = true
    #unless entry.limit_price > entry.work_price
    #  transcript.puts "entry:#{entry.entry_id} bad limit_price:#{entry.limit_price}"
    #  rtn = false
    #end
    unless %w(long short).include?(entry.side)
      transcript.puts "entry:#{entry.entry_id} unknown side:#{entry.side}"
      rtn = false
    end
    unless LongEntrySignals.include?(entry.entry_signal)
      transcript.puts "entry:#{entry.entry_id} unknown entry_signal:#{entry.entry_signal}"
      rtn = false
    end
    unless entry.work_price.is_a?(Numeric)
      transcript.puts "entry:#{entry.entry_id} Invalid work_price:#{entry.work_price}"
      rtn = false
    end
    unless entry.limit_price.is_a?(Numeric)
      transcript.puts "entry:#{entry.entry_id} Invalid limit_price:#{entry.limit_price}"
      rtn = false
    end
    rtn
  rescue
    transcript.puts "invalid entry!, entry:#{entry.dump}"
    false
  end

  def get_work_price(sec_id, side)
    ((side == "long") ? @lvc.high(sec_id) : @lvc.low(sec_id)).to_f
  end

  def size_kelly_criterion
    0
  end

  def size_van_tharp
    0
  end

  # Defined Risk Model
  def DRM_risk_dollars(account_proxy)
    #puts "DRM_risk_dollars: #{account_proxy.risk_dollars}"
    account_proxy.risk_dollars
  end

  # Core Equity Model
  def CEM_risk_dollars(account_proxy)
    account_proxy.buying_power * account_proxy.position_percent / 100.0
  end

  # Total Equity Model
  def TEM_risk_dollars(account_proxy)
    (account_proxy.buying_power + account_proxy.long_market_value) * 
      account_proxy.position_percent / 100.0
  end

  # Reduced Total Equity Model
  def RTEM_risk_dollars(account_proxy)
    debug "RTEM_risk_dollars: account_proxy.buying_power=#{account_proxy.buying_power}"
    debug "RTEM_risk_dollars: account_proxy.long_locked_in=#{account_proxy.long_locked_in}"
    (account_proxy.buying_power + account_proxy.long_locked_in) *
       account_proxy.position_percent / 100.0
  end
end

