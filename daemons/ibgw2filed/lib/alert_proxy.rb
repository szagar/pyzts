$: << "#{ENV['ZTS_HOME']}/etc"
require 'store_mixin'
require 'log_helper'
#require 'redis_store'

class AlertStore # < RedisStore
  include Store
  include LogHelper
  def initialize
    #show_info "AlertStore#initialize"
    super
  end
end

class  AlertProxy
  include LogHelper
  def initialize(params, persister=AlertStore.new)
    @persister = persister
    @alert_id = params.fetch("alert_id") { create_alert(params) }
  end

  def create_alert(params)
    show_info "AlertProxy#create_alert(#{params})"
    set_defaults(params)
    @persister.create(params)
  end

  def valid?
    true #(ref_id.is_a? Integer) && (sec_id.is_a? Integer)
  end

  def info
    persister_name
  end

  def dump
    @persister.dump(@alert_id)
  end

  def alert_id
    @alert_id
  end

  def level
    @persister.getter(@alert_id,"level").to_f
  end

  def ohlc
    @persister.getter(@alert_id,"ohlc")
  end

  def op
    @persister.getter(@alert_id,"op")
  end

  def sec_id
    @persister.getter(@alert_id,"sec_id").to_i
  end

  def ref_id
    @persister.getter(@alert_id,"ref_id").to_i
  end

  def tif
    @persister.getter(@alert_id,"tif")
  end

  def status
    @persister.getter(@alert_id,"status")
  end

  def open?
    @persister.getter(@alert_id,"status") == "open"
  end

  def one_shot?
    @persister.getter(@alert_id,"one_shot")
  end

  def expire
    @persister.setter(@alert_id, "status", "expired")
  end

  def close
    debug "AlertProxy#close @alert_id=#{@alert_id}"
    @persister.setter(@alert_id, "status", "closed")
  end

  def triggered?(price,keep=false)
    #debug "triggered(sec_id=#{sec_id}) = Float(#{price}).send(#{op}, #{level}) && #{status} == open" 
    debug "price = #{price}"
    debug "op    = #{op}"
    debug "level = #{level}"
    debug "status= #{status}"
    triggered = Float(price).send(op, level) && status == "open" 
    debug "AlertProxy#triggered? triggered=#{triggered}"
    close if (triggered && one_shot? && !keep) 
    triggered
  rescue
    warn "AlertProxy#triggered thru exception"
    false
  end

  private

  def persister_name
    @persister.whoami
  end

  def set_defaults(params)
    params[:tif]             ||= 'Day'
    params[:status]          ||= 'open'
    params[:one_shot]        ||= true
  end
end

