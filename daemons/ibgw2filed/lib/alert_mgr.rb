require "alert_mgr_store"
require "alert_proxy"
require "log_helper"

class AlertMgr
  include LogHelper

  def initialize(persister=AlertMgrStore.new)
    @store = persister
  end

  def entry_exists?(id)
    @store.entry_exists?(id)
  end

  def add_alert(src, ref_id, params)
    show_info "AlertMgr#add_alert(src: #{src},ref_id: #{ref_id},#{params})"
    alert = AlertProxy.new(ref_id:   ref_id,
                           sec_id:   params[:sec_id],
                           op:       params[:op],
                           level:    params[:level],
                           one_shot: params.fetch(:one_shot) {true}  )
    debug "AlertMgr: @store.add_alert(#{src}, #{params[:sec_id]}, #{alert})"
    @store.add_alert(src, params[:sec_id], alert)
    alert.alert_id
  end

  def triggered(src, sec_id, high, low, keep=false)
    debug "AlertMgr#triggered(#{src}, #{sec_id}, #{high}, #{low}, #{keep})"
    results = alerts(src, sec_id).keep_if do |alert| 
      price = (alert.op[/>/,0] ? high : low)
      debug "AlertMgr#triggered: price = #{price}"
      stat = alert.triggered?(price,keep)
    end
    debug "AlertMgr#triggered: results=#{results}"
    results.map { |alert| alert.ref_id }
  end

  def adjust_for_split(src,sec_id,pos_id,ratio)
    puts "adjust_for_split(#{src},#{sec_id},#{pos_id},#{ratio})"
    @store.adj_position_alert_levels(src,sec_id,pos_id,ratio)
  end

  def cleanup(src)
    @store.check_then_delete(src)
  end

  def close_alerts(src, sec_id, ref_id)
    debug "AlertMgr#close_alerts(#{src}, #{sec_id}, #{ref_id})"
    alerts(src,sec_id,ref_id).each { |alert| debug "AlertMgr#close_alerts: id=#{alert.alert_id}"; alert.close }
  end

  def purge_alerts(src, sec_id, ref_id, current_alert_id)
    debug "AlertMgr#purge_alerts(#{src}, #{sec_id}, #{ref_id}, #{current_alert_id})"
    alerts(src,sec_id,ref_id).each { |alert|
      debug "AlertMgr: alert.alert_id(#{alert.alert_id}/#{alert.alert_id.class}) == current_alert_id(#{current_alert_id}/#{current_alert_id.class}) => #{alert.alert_id == current_alert_id}"
      alert.close unless alert.alert_id == current_alert_id
    }
  end

  def all_alerts(src, sec_id, ref_id)
    @store.alerts(src,sec_id,ref_id,true)
  end

  def alerts(src, sec_id, ref_id="*")
    @store.alerts(src, sec_id, ref_id)
  end
  ##############
  private
  ##############

end
