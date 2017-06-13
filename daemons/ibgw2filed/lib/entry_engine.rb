$: << "#{ENV['ZTS_HOME']}/etc"

require "stringio"
require "zts_constants"
require "setup_struct"
require "alert_mgr"
require "alert_mgr_store"
require "entry_proxy"
require "last_value_cache"
require "exit_mgr"
require "mkt_subscriptions"
require "s_m"
require "misc_helper"
require "log_helper"

class NoSecIdException   < StandardError; end
class InvalidSetupError  < StandardError; end
class SideNotKnown       < StandardError; end

class EntryEngine
  include ZtsConstants
  include LogHelper

  attr_reader :lvc, :sequencer, :mkt_subs

  def initialize
    @alert_mgr  = AlertMgr.new(persister=AlertMgrStore.new)
    @lvc        = LastValueCache.instance
    @sequencer  = SN.instance
    @mkt_subs     = MktSubscriptions.instance
    @sec_master = SM.instance
    @exit_mgr   = ExitMgr.instance

    #20150214
    #@md_subscriptions      = Hash.new
  end
  
  def eligible_entries(setup)
    debug "eligible_entries  src = #{setup.setup_src}"
    if (setup.sec_id = @sec_master.sec_lookup(setup.ticker)).nil?
      warn("entry_engine: @sec_master.sec_lookup for =#{setup.ticker}= FAILED.")
      raise NoSecIdException.new, "EntryEngine#eligible_entries(#{setup.ticker})"
    end

    setup.setup_id = sequencer.next_setup_id.to_s
    
    ## from setup:
    ##    trade_type           - validate
    ##    trailing_stop_type   - validate
    ##    entry_stop_price     - validate for pre-buys
    ##

    entry = create_entry(setup)

  rescue NoSecIdException, InvalidSetupEntry => e
    warn "#{e.class}: <#{e.message}>"
    warn "setup: #{setup}"
    #entry.notes += "Exception thrown(eligible_entries)."
    #entry.status = "canceled"
    []
  end
########################

  def setup_entries(setup)
    trans = StringIO.new
    raise InvalidSetupError.new, trans.string unless (valid_setup?(setup,trans))

    entries = Array.new
    Array(eligible_entries(setup)).each do |entry|
      next unless entry.status == "open"
      show_info "new entry: s/e:#{entry.setup_id}/#{entry.entry_id} #{entry.side} "\
                "#{entry.ticker}(#{entry.sec_id}) at #{entry.limit_price} "\
                "from #{entry.setup_src}/#{entry.entry_signal}  " \
                "#{entry.trailing_stop_type} trailing stop"
      show_info "tags=#{entry.tags}"
      setup_alert_for_entry(entry.entry_id, entry.side, entry.sec_id, entry.entry_stop_price)
      entries.push(entry.entry_id)
    end
    entries
  rescue InvalidSetupError => e
    warn "InvalidSetupError exception, setup: #{setup}"
    warn "#{e.class}: <#{e.message}>   from <#{e.backtrace.first}>??"
    []
  end

  def triggered_entries(bar)
    show_info "results = @alert_mgr.triggered(#{self.class}, #{bar.sec_id}, #{bar.high}, #{bar.low})"
    results = @alert_mgr.triggered(self.class, bar.sec_id, bar.high, bar.low)  # array of AlertProxy
    show_info "EntryEngine#triggered_entries: results=#{results}"
    entry_sanity_screen(results)
  end

  def entry_sanity_screen(entries)
    checked_entries = []
    entries.each { |entry_id|
      (@alert_mgr.entry_exists?(entry_id)) ? checked_entries << entry_id : \
                  warn("Entry #{entry_id} NOT found in Alert Mgr, #{__FILE__}:#{__LINE__}")
    }
    checked_entries
  end
  
  def alerts(sec_id)
    @alert_mgr.alerts(self.class, sec_id)
  end

  def status_change(entry_id, status)
    show_info "EntryEngine#status_change(#{entry_id}, #{status})"
    EntryProxy.new(entry_id: entry_id).set_status(status)
  end

  def create_scale_in_entry(entry_id, oneR)
    attribs = {entry_stop_price: entry.entry_stop_price + oneR}
    entry = EntryProxy.new(entry_id: entry_id).clone(attribs)
  end

  ############
  private
  ############

  def create_entry(setup)
    debug "entry = EntryProxy.new(#{setup})"
    entry = EntryProxy.new(setup.attributes)

    entry.expire_at_next_close
    entry.status             = "open"
    entry.support          ||= support_for_entry(entry)

    entry.work_price         = get_work_price(setup).round(4)
    entry.entry_stop_price ||= calc_stop_from_work_price(entry.work_price, setup.side)
    entry.est_stop_loss      = @exit_mgr.est_stop_loss(entry)
    entry.est_risk_share     = (entry.work_price - entry.est_stop_loss).abs
    entry.limit_price        = calc_limit_from_stop_price(entry.entry_stop_price, setup.side).round(2)

    puts "EntryEngine#create_entry: setup=#{setup.attributes}"
    puts "EntryEngine#create_entry: entry=#{entry.attributes}"

    #unless good_risk_reward(setup,entry)
    unless good_risk_reward(entry)
      entry.notes += "Bad Risk/Reward."
      entry.status = "canceled"
      show_info "EntryEngine: ticker:#{entry.ticker} notes:#{entry.notes} status:#{entry.status} risk:#{entry.est_risk_share}"
    end
    entry
  end

  def good_risk_reward(entry)
    puts "MIN_RUN_PTS=#{MIN_RUN_PTS}"
    puts "MIN_RTN_RISK=#{MIN_RTN_RISK}"
    case entry.trade_type
    when "Swing"
      (entry.avg_run_pt_gain >= MIN_RUN_PTS)  &&
      (entry.avg_run_pt_gain.to_f / entry.est_risk_share.to_f) >= MIN_RTN_RISK
    when "Position"
      (entry.tgt_gain_pts >= MIN_TGT_PT_GAIN) &&
      (entry.tgt_gain_pts.to_f / entry.est_risk_share.to_f) >= MIN_RTN_RISK
    when "Trend"
      true
    else
      warn "Trade Type: #{entry.trade_type} not recognized for setup: #{entry.setup.id}"
      false
    end
  rescue => e
    warn e.mesage
    warn "EntryEngine#good_risk_reward exception"
    false
  end

  def support_for_entry(entry)
    case entry.trade_type
    when "Swing"
      MiscHelper::first_numeric(entry.support, entry.weak_support)
    when "Position"
      MiscHelper::first_numeric(entry.support, entry.moderate_support, entry.strong_support)
    when "Trend"
      MiscHelper::first_numeric(entry.support, entry.strong_support, entry.moderate_support, entry.weak_support)
    else
      warn "EntryEngine#support_for_entry: support level could NOT be determined"
      nil
    end
  end

  def valid_atr?(sec_id)
    true
  end

  def valid_price?(price)
    (MiscHelper::is_a_number?(price) && price > 0.0)
  end

  def valid_setup?(setup, transcript=StringIO.new)
    rtn = true
    unless (setup.setup_src =~ /\w+/)
      transcript.puts "setup: unknown setup_src:#{setup.setup_src}"
      rtn = false
    end
    unless LongEntrySignals.include?(setup.entry_signal)
      transcript.puts "setup: unknown entry_signal:#{setup.entry_signal}"
      rtn = false
    end
    unless %w(long short).include?(setup.side)
      transcript.puts "setup: unknown side:#{setup.side}"
      rtn = false
    end
    unless (setup.ticker =~ /\w+/)
      transcript.puts "setup: missing ticker:#{setup.ticker}"
      rtn = false
    end
    case setup.entry_signal
    when "pre-buy", "systematic"
      unless (setup.entry_stop_price.is_a?(Numeric) && setup.entry_stop_price > 0)
        transcript.puts "setup: missing entry_stop_price"
        rtn = false
      end
    end
    rtn
  end

  def calc_position_rr(work_price, setup)
    support = MiscHelper::first_numeric(setup.support, setup.moderate_support)
    raise InvalidSetupError.new "missing support" unless valid_price?(support)
    (setup.tgt_gain_pts < MIN_TGT_PT_GAIN) ? 0.0 :
                       (setup.tgt_gain_pts.to_f /
                          (work_price.to_f - support.to_f))
  rescue InvalidSetupError => e
    warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    warn "setup: #{setup}"
  end

  def calc_swing_rr(work_price, setup)
    support = MiscHelper::first_numeric(setup.support, setup.weak_support, setup.moderate_support)
    if (setup.trailing_stop_type == "atr")
      return MIN_RTN_RISK
    end
    raise InvalidSetupError.new "missing support" unless valid_price?(support)
    (setup.avg_run_pt_gain < MIN_RUN_PTS) ? 0.0 :
                       (setup.avg_run_pt_gain.to_f /
                           (work_price.to_f - support))
  rescue InvalidSetupError => e
    warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    warn "setup: #{setup}"
    0.0
  end

  def setup_alert_for_entry(entry_id, side, sec_id, entry_stop_price)
    show_action "setup Alert for entry: entry_id: #{entry_id}, side: #{side}, sec_id: #{sec_id}, stop price: #{entry_stop_price}"
    if side == "long"
      market_above_alert(entry_id, sec_id, entry_stop_price)
    else
      market_below_alert(entry_id, sec_id, entry_stop_price)
    end
  end

  def market_above_alert(ref_id, sec_id, level, one_shot=true)
    @alert_mgr.add_alert(self.class, ref_id,  { sec_id: sec_id,
                                                op:       :>=,
                                                level:  level,
                                                one_shot: true } )
  end

  def market_below_alert(ref_id, sec_id, level, one_shot=true)
    @alert_mgr.add_alert(self.class, ref_id,  { sec_id: sec_id,
                                                op:       :<=,
                                                level:  level,
                                                one_shot: true } )
  end

  def get_work_price(setup)
    return setup.entry_stop_price.to_f if (setup.entry_stop_price.is_a?(Numeric) && setup.entry_stop_price > 0)
    (setup.side == long) ? lvc.high(setup.sec_id).to_f : lvc.low(setup.sec_id).to_f
  end

=begin
  def get_work_price(side, sec_id)
    case side
    when "long"
      work_price  = lvc.high(sec_id).to_f
    when "short"
      work_price  = lvc.low(sec_id).to_f
    else
      warn "get_work_price: side(#{side}) not known"
    end
  end
=end

  def get_sidex(side)
    sidex = case side
            when "long"
              1 
            when "short"
              -1
            else
              warn "get_sidexside(#{side}) not known"
            end
    sidex
  end

  def calc_limit_from_stop_price(stop_price, side)
    case side
    when "long"
      limit_price = stop_price + ((stop_price < 10) ?  0.25 : 0.375)
    when "short"
      limit_price = stop_price - ((stop_price < 10) ?  0.25 : 0.375)
    else
      warn "calc_limit_from_stop_price: side(#{side}) not known"
      raise SideNotKnown, "EntryEngine#calc_limit_from_stop_price"
    end
  end

  def calc_stop_from_work_price(work_price, side)
    case side
    when "long"
      stop_price = work_price + ((work_price < 10) ? 0.12 : 0.25)
    when "short"
      stop_price = work_price - ((work_price < 10) ? 0.12 : 0.25)
    else
      warn "calc_stop_from_work_price: side(#{side}) not known"
      raise SideNotKnown, "EntryEngine#calc_stop_from_work_price"
    end
  end
end
