require "singleton"
require "last_value_cache"
require "misc_helper"
require "store_mixin"
require "date_time_helper"
require "log_helper"

TimedExits = "exits:timed"

class InvalidExitError < StandardError; end
class InvalidSetupEntry < StandardError; end

class ExitMgr
  include Singleton
  include LogHelper
  include Store

  def initialize
    @lvc   = LastValueCache.instance
  end

  def create_timed_exit(pos_id, time_exit)
    debug "ExitMgr#create_timed_exit(pos_id: #{pos_id}, time_exit: #{time_exit})"
    raise InvalidExitError.new, "could not set exit time(#{time_exit})" unless time_exit.to_s =~ /\d+/
    days = time_exit.to_i 
    exit_day = DateTimeHelper::future_trade_day(days)
    redis.zadd TimedExits, exit_day, pos_id
    save_exit(pos_id, "timed", exit_day)
  #rescue InvalidTradeError => e
  #  warn "could not create timed exit for pos: #{pos_id}"
  #  warn e.message
  end

  def timed_exits
    today = DateTimeHelper::integer_date
    results = redis.zrangebyscore TimedExits, 0, today
    #expire_timed_alerts(day)
    results
  end

  def expire_timed_alerts(day=DateTimeHelper::integer_date)
    results = Array(redis.zremrangebyscore TimedExits, 0, day)
    results.each { |pos_id| 
      next unless pos_id > 0
      delete_exit(pos_id, "timed", day)
    }
  end

  def est_stop_loss(entry)
    debug "ExitMgr#est_stop_loss(#{entry.attributes})"
    debug "ExitMgr#est_stop_loss: trailing_stop_stype=#{entry.trailing_stop_type}"
    case entry.trailing_stop_type
    when "manual"
      manual_calc(entry.stop_loss_price,entry.work_price)
    when "support"
      raise InvalidSetupEntry.new("Could not calc risk/share from support") unless valid4support?(entry.support,entry.work_price) 
      support_calc(entry.sidex,entry.support,entry.work_price)
    when "support_x"
      raise InvalidSetupEntry.new("Could not calc risk/share from support") unless valid4support?(entry.support,entry.work_price) 
      support_x_calc(entry.sidex,entry.support,entry.work_price)
    when 'risk_per_sh'
      raise InvalidSetupEntry.new("Could not calc risk/share from rps_exit") unless valid4rps?(entry.rps_exit) 
      
    when "ema"
      raise InvalidSetupEntry.new("Could not calc risk/share from ema") unless valid4ema?(entry.side,entry.sec_id)
      ema_calc(entry.side,entry.sec_id)
    when "atr"
      #atr_factor = 1.0  # use min atr factor for estimate
      atr_factor = (entry.trade_type == "Swing") ? 1.0 : 2.7
      atr        = entry.atr.to_f || @lvc.atr(entry.sec_id).to_f
      raise InvalidSetupEntry.new("Could not calc risk/share from atr") unless valid4atr?(entry.sec_id,atr,atr_factor)
      atr_calc(entry.sidex,entry.sec_id,atr,atr_factor,entry.work_price)
    when "tightest"
      atr_factor = (entry.trade_type == "Swing") ? 1.0 : 2.7
      tightest_calc(entry.side,entry.sec_id,atr_factor,entry.work_price,entry.support)
    end
  end

  def atr(pos, price)
    show_info "ExitMgr#atr(#{pos.dump},#{price})"
    show_info "sec_id = #{pos.sec_id}  atr_factor=#{pos.atr_factor}   sidex=#{pos.sidex}"
    atr_value = pos.update_atr
    valid4atr?(pos.sec_id,nil,pos.atr_factor) ? atr_calc(pos.sidex,pos.sec_id,atr_value,pos.atr_factor,price) : handle_error(pos,price)
  end

  def support(pos, price)
    show_info "ExitMgr#support(#{pos.dump},#{price})"
    valid4support?(pos.support,price) ? support_calc(pos.sidex,pos.support,price) : handle_error(pos,price)
  end

  def support_x(pos, price)
    show_info "ExitMgr#support_x(#{pos.dump},#{price})"
    valid4support?(pos.support,price) ? support_x_calc(pos.sidex,pos.support,price) : handle_error(pos,price)
  end

  def risk_per_sh(pos, price)
    show_info "ExitMgr#risk_per_sh(#{pos.dump},#{price})"
    valid4rps?(pos.rps_exit) ? risk_per_sh_calc(pos.sidex,pos.rps_exit,price) : handle_error(pos,price)
  end

  def ema(pos, price)
    show_info "ExitMgr#ema(#{pos.dump},#{price})"
    valid4ema?(pos.side,pos.sec_id) ? ema_calc(pos.side,pos.sec_id) : handle_error(pos,price)
  end

  def manual(pos, price)
    show_info "ExitMgr#manual(#{pos.dump},${price})"
    valid4manual?(pos,price) ? manual_calc(current_stop,price) : handle_error(pos,price)
  end

  def tightest(pos, price)
    show_info "ExitMgr#tightest(#{pos.dump},${price})"
    results = tightest_calc(pos.side,pos.sec_id,pos.atr_factor,price,pos.support)
    valid4tightest?(pos,results) ? results : handle_error(pos,price)
  end

  def timed(pos, price)
    show_info "ExitMgr#timed(#{pos.dump},${price})"
    valid4atr?(pos.sec_id,nil,pos.atr_factor) ? atr_calc(pos.sidex,pos.sec_id,nil,pos.atr_factor,price) : handle_error(pos,price)
  end

  def save_exit(pos_id,type,params)
    redis.sadd "exitstore:#{pos_id}", "#{type}:#{params}"
  end

  ##############
  private
  ##############

  def delete_exit(pos_id,type,params)
    redis.srem "exitstore:#{pos_id}", "#{type}:#{params}"
  end

  def atr_calc(sidex, sec_id, atr, atr_factor, price)
    show_info "atr_calc(#{sidex}, #{sec_id}, #{atr}, #{atr_factor}, #{price})"
    atr ||= @lvc.atr(sec_id)
    show_info "ExitMgr(#{sec_id})#atr_calc: atr = #{atr}"
    r   = (atr * atr_factor.to_f).round(4)
    show_info "ExitMgr(#{sec_id})#atr_calc:   r = #{r}"
    new_stop = (price - sidex * r).round(2)
    show_info "ExitMgr(#{sec_id})#atr_calc: new_stop = #{new_stop}"
    new_stop
  end

  def support_calc(sidex, support, price)
    show_info "ExitMgr#support_calc(#{sidex}, #{support}, #{price})"
    return nil unless MiscHelper::is_a_number?(support) && support > 0.0
    fudge    = (price < 10.0) ? 0.12 : 0.25
    fudge    = 0.0 if price < 1.0
    show_info "ExitMgr#support_calc: fudge = #{fudge}"
    new_stop = support.to_f - sidex * fudge
    show_info "ExitMgr#support_calc: new_stop = #{new_stop}"
    #new_stop_trigger = nil
    #[new_stop.round(2), (new_stop_trigger.round(2) rescue nil)]
    new_stop.round(2)
  end

  def support_x_calc(sidex, support, price)
    show_info "ExitMgr#support_x_calc(#{sidex}, #{support}, #{price})"
    return nil unless MiscHelper::is_a_number?(support) && support > 0.0
    fudge    = 0.0
    show_info "ExitMgr#support_x_calc: fudge = #{fudge}"
    new_stop = support.to_f - sidex * fudge
    show_info "ExitMgr#support_x_calc: new_stop = #{new_stop}"
    new_stop.round(2)
  end

  def risk_per_sh_calc(sidex,rps_exit,price)
    debug "ExitMgr#risk_per_sh_calc(#{sidex},#{rps_exit},#{price})"
    new_stop = price - sidex * rps_exit
    new_stop.round(2)
  end

  def ema_calc(side, sec_id)
    show_info "ExitMgr#ema_calc(#{side}, #{sec_id})"
    level = (side == "long") ? "low" : "high"
    show_info "ExitMgr#ema_calc: level=#{level}"
    new_stop = @lvc.ema(sec_id,level,34)
    show_info "ExitMgr#ema_calc: new_stop=#{new_stop}"
    #new_stop_trigger = nil
    #[new_stop.round(2), (new_stop_trigger.round(2) rescue nil)]
    new_stop
  end

  def manual_calc(stop_loss_price,work_price)
    show_info "ExitMgr#manual_calc(#{stop_loss_price},#{work_price})"
    new_stop = stop_loss_price
    new_stop
  end

  def tightest_calc(side,sec_id,atr_factor,price,support)
    sidex = (side == "short") ? -1 :1
    a = Array.new
    a[0] = atr_calc(sidex,sec_id,nil,atr_factor,price) rescue nil
    a[1] = support_calc(sidex,support,price)           rescue nil
    a[2] = ema_calc(sidex,sec_id)                      rescue nil
    show_info "ExitMGR#tightest_calc(#{sec_id}):      atr stop = #{a[0]}"
    show_info "ExitMGR#tightest_calc(#{sec_id}):  support stop = #{a[1]}"
    show_info "ExitMGR#tightest_calc(#{sec_id}):      ema stop = #{a[2]}"
    side == "long" ? a.compact.max  : a.compact.min
  end

  def valid4rps?(rps)
    (MiscHelper::is_a_number?(rps) && rps > 0.0)
  end

  def valid4atr?(sec_id,atr,atr_factor)
    #risk_share < (0.25 * price)
    atr ||= @lvc.atr(sec_id)
    show_info "ExitMgr#valid4atr?:        atr = #{atr}"
    show_info "ExitMgr#valid4atr?: atr_factor = #{atr_factor}"
    (MiscHelper::is_a_number?(atr_factor) && atr_factor > 0.0) &&
    (MiscHelper::is_a_number?(atr) && atr > 0.0)
  rescue
    false
  end

  def valid4support?(support,price)
    debug "ExitMgr#valid4support: support=#{support}  price=#{price}"
    valid = false
    valid = true if (price >  5.0) && (price - support).abs < (price * 0.25) 
    valid = true if (price <= 5.0) && (price - support).abs < (price * 0.50) 
    warn "(#{price}-#{support}).abs/#{price} = #{(price-support).abs/price*100.0}% risk too large, skip trade" unless valid
    valid
  rescue 
    false
  end

  def valid4ema?(side,sec_id)
    level = (side == "long") ? "low" : "high"
    ema = @lvc.ema(sec_id,level,34)
    (MiscHelper::is_a_number?(ema) && ema > 0.0)
  rescue
    false
  end

  def valid4manual?(pos,price)
    (MiscHelper::is_a_number?(price) &&
    (price - pos.avg_entry_px).abs <= (pos.avg_entry_px*0.25))
  rescue
    false
  end

  def valid4tightest?(pos,stoploss)
    (stoploss - pos.avg_entry_px).abs <= (pos.avg_entry_px * 0.25)
  rescue
    false
  end

  def handle_error(pos,price)
    warn "Error calculating stop loss for pos_id=#{pos.pos_id}, using 25% stop"
    new_stop = price.to_f * (1  - pos.sidex * 0.25)
    new_stop
  end
end
