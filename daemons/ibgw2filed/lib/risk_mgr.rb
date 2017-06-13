#require 'singleton'
require 'alert_mgr'
require 'portfolio_mgr'
require 'exit_mgr'
require 'log_helper'
require "last_value_cache"

class RiskMgr
#  include Singleton
  include LogHelper

  def initialize
    @alert_mgr = AlertMgr.new
    @portf_mgr = PortfolioMgr.instance
    @exit_mgr = ExitMgr.instance
    @lvc       = LastValueCache.instance
  end

  def update_trailing_stop(pos_id,price=nil)
    return unless @portf_mgr.position_is_open?(pos_id)
    return if @portf_mgr.position_is_timed?(pos_id)
    pos = @portf_mgr.position(pos_id)

    rtn = pos.update_stop_price(price || @lvc.last(pos.sec_id))
    update_alert_for_exit(pos_id, pos.side, pos.sec_id,
                          pos.current_stop) if rtn
  end

  def create_target_exit(pos_id,price)
    debug "RiskMgr#create_target_exit(#{pos_id},#{price})"
    return unless @portf_mgr.position_is_open?(pos_id)
    return if @portf_mgr.position_is_timed?(pos_id)
    pos = @portf_mgr.position(pos_id)
    alert_id = (pos.side == "long") ? market_above_alert(pos_id, pos.sec_id, price)
                                : market_below_alert(pos_id, pos.sec_id, price)
  end

  def triggered_exits(bar,do_not_exit_flag)
    show_info "triggered_exits: exits = @alert_mgr.triggered(#{self.class}, #{bar.sec_id}, #{bar.high}, #{bar.low})"
    exits = @alert_mgr.triggered(self.class, bar.sec_id, bar.high, bar.low, do_not_exit_flag)
    show_info "triggered_exits: exits=#{exits}"
    exits.each_with_object([]) { |pos_id, arr|
      do_not_exit_flag ? (warn "Do Not Exit set for #{bar.sec_id}") : (show_info "RiskMgr: create unwind order for pos #{pos_id}")
      next if do_not_exit_flag
      #order = @portf_mgr.unwind_order(pos_id)
      #show_info "RiskMgr: unwind order is #{(order.valid?) ? "valid" : "invalide"}"
      #arr << order if order.valid?
      arr << pos_id
    }
  end

  def timed_exits
    puts "RiskMgr#timed_exits exits = @exit_mgr.timed_exits"
    exits = @exit_mgr.timed_exits
    puts "RiskMgr#timed_exits exits = #{exits}"
    orders = exits.each_with_object([]) do |pos_id, arr|
      order = @portf_mgr.unwind_order(pos_id)
      arr << order if order.valid?
    end
    puts "RiskMgr#timed_exits: @exit_mgr.expire_timed_alerts"
    @exit_mgr.expire_timed_alerts
    puts "RiskMgr#timed_exits: @exit_mgr.expire_timed_alerts return"
    orders
  end

  #def close_position_exit_alerts(pos)
  #  debug "RiskMgr#close_position_exit_alerts"
  #  # closed all open RiskMgr alerts for for sec_id & pos_id 
  #  @alert_mgr.close_alerts(self.class, pos.sec_id, pos.pos_id)
  #end

  #####################
  private
  #####################

  def purge_position_exit_alerts(pos_id, sec_id, current_alert_id)
    # close all open alerts except current open alert for sec_id & pos_id
    debug "RiskMgr#purge_position_exit_alerts(#{pos_id}, #{sec_id}, #{current_alert_id})"
    @alert_mgr.purge_alerts(self.class, sec_id, pos_id, current_alert_id)
  end

  def update_alert_for_exit(pos_id, side, sec_id, price)
    show_info "update_alert_for_exit(pos_id: #{pos_id}, side: #{side}, sec_id: #{sec_id}, price: #{price})"
    #close_position_exit_alerts(pos_id, sec_id)
    alert_id = (side == "long") ? market_below_alert(pos_id, sec_id, price)
                                : market_above_alert(pos_id, sec_id, price)
    purge_position_exit_alerts(pos_id, sec_id, alert_id)
  end

  def market_above_alert(ref_id, sec_id, level, one_shot=true)
    #puts "market_above_alert(#{ref_id}, #{sec_id}, #{level}, #{one_shot})"
    @alert_mgr.add_alert(self.class, ref_id,  { sec_id: sec_id,
                                                op:       :>=,
                                                level:  level,
                                                one_shot: true } )
  end

  def market_below_alert(ref_id, sec_id, level, one_shot=true)
    #puts "market_below_alert(#{ref_id}, #{sec_id}, #{level}, #{one_shot})"
    alert_id = @alert_mgr.add_alert(self.class, ref_id,  { sec_id: sec_id,
                                                op:       :<=,
                                                level:  level,
                                                one_shot: true } )
    debug "RiskMgr#market_below_alert: alert_id = #{alert_id}"
    alert_id
  end

  def look_up_alert(ref_id)
  end
  def look_up_alert(ref_id)
  end

end
