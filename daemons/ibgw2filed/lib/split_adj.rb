#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"
require 'store_mixin'

require 'active_record'
require 'logger'
require "log_helper"
require 'alert_mgr'

class Positions < ActiveRecord::Base; end

class SplitAdj
  include LogHelper
  include Store

  def initialize
    Zts.configure { |config| config.setup }
    logname = File.dirname(__FILE__) + '/..' + '/log/' + File.basename(__FILE__, ".rb")+'_AR.log'
    show_info "logname=#{logname}"
    ActiveRecord::Base.logger = Logger.new(logname)
    ActiveRecord::Base.configurations = YAML::load(IO.read(ENV["ZTS_HOME"]+'/etc/database.yml'))
    ActiveRecord::Base.establish_connection(ENV["ZTS_ENV"].to_sym)
  end

  def cleanup
    ActiveRecord::Base.remove_connection()
  end

  def run(data)
    puts "run(#{data})"
    rec = form_record(data)
    warn "Could not adjust for split on position: #{data[:pos_id]}" unless rec
    split_adj(rec) if rec
  end

  #################
  private
  #################

  def form_record(data)
    return false unless valid_id?(data[:pos_id])
    { pos_id:  data[:pos_id].to_i,
      ratio:   data[:ratio].to_f,
    }
  end

  def valid_str?(s); s =~ /^\w+/; end
  def valid_id?(s); s =~ /^\d+/; end

  def split_adj(rec)
    puts "split_adj: rec=#{rec}"
    show_action "Adjust position(#{rec[:pos_id]}) for 1:#{rec[:ratio]} split"
    db_adj(rec)
    update_redis(rec)
    adj_exit_alerts(rec)
  end

  def update_redis(rec)
    puts "update_redis(#{rec})"
    ratio              = rec[:ratio].to_f
    atr                = (redis.hget "pos:#{rec[:pos_id]}", "atr").to_f
    mark_px            = (redis.hget "pos:#{rec[:pos_id]}", "mark_px").to_f
    avg_entry_px       = (redis.hget "pos:#{rec[:pos_id]}", "avg_entry_px").to_f
    current_stop       = (redis.hget "pos:#{rec[:pos_id]}", "current_stop").to_f
    current_risk_share = (redis.hget "pos:#{rec[:pos_id]}", "current_risk_share").to_f
    position_qty       = (redis.hget "pos:#{rec[:pos_id]}", "position_qty").to_f
    quantity           = (redis.hget "pos:#{rec[:pos_id]}", "quantity").to_f

    puts "ratio              = #{ratio}"
    puts "atr                = #{atr}"
    puts "mark_px            = #{mark_px}"
    puts "avg_entry_px       = #{avg_entry_px}"
    puts "current_stop       = #{current_stop}"
    puts "current_risk_share = #{current_risk_share}"
    puts "position_qty       = #{position_qty}"
    puts "quantity           = #{quantity}"

    puts "redis.hset pos:#{rec[:pos_id]}, atr, #{atr / ratio}"
    puts "redis.hset pos:#{rec[:pos_id]}, mark_px, #{mark_px / ratio}"
    puts "redis.hset pos:#{rec[:pos_id]}, avg_entry_px, #{avg_entry_px / ratio}"
    puts "redis.hset pos:#{rec[:pos_id]}, current_stop, #{current_stop / ratio}"
    puts "redis.hset pos:#{rec[:pos_id]}, current_risk_share, #{current_risk_share / ratio}"
    puts "redis.hset pos:#{rec[:pos_id]}, position_qty, #{(position_qty * ratio).ceil}"
    puts "redis.hset pos:#{rec[:pos_id]}, quantity, #{(quantity * ratio).ceil}"

    redis.hset "pos:#{rec[:pos_id]}", "atr", atr / ratio
    redis.hset "pos:#{rec[:pos_id]}", "mark_px", mark_px / ratio
    redis.hset "pos:#{rec[:pos_id]}", "avg_entry_px", avg_entry_px / ratio
    redis.hset "pos:#{rec[:pos_id]}", "current_stop", current_stop / ratio
    redis.hset "pos:#{rec[:pos_id]}", "current_risk_share", current_risk_share / ratio
    redis.hset "pos:#{rec[:pos_id]}", "position_qty", (position_qty * ratio).ceil
    redis.hset "pos:#{rec[:pos_id]}", "quantity", (quantity * ratio).ceil
  end
 
  def db_adj(data)
    rec = Positions.find_by_pos_id(data[:pos_id])
    ratio              = data[:ratio].to_f
    atr                = rec[:atr].to_f
    mark_px            = rec[:mark_px].to_f
    avg_entry_px       = rec[:avg_entry_px].to_f
    current_stop       = rec[:current_stop].to_f
    current_risk_share = rec[:current_risk_share].to_f
    position_qty       = rec[:position_qty].to_f
    quantity           = rec[:quantity].to_f

    puts "ratio              = #{ratio}"
    puts "atr                = #{atr}"
    puts "avg_entry_px       = #{avg_entry_px}"
    puts "current_stop       = #{current_stop}"
    puts "current_risk_share = #{current_risk_share}"
    puts "position_qty       = #{position_qty}"
    puts "quantity           = #{quantity}"

    attr = {atr:                atr/ratio,
            avg_entry_px:       avg_entry_px/ratio,
            current_stop:       current_stop/ratio,
            current_risk_share: current_risk_share/ratio,
            position_qty:       (position_qty*ratio).ceil,
            quantity:           (quantity*ratio).ceil}
    puts "attr=#{attr}"
    rec.update_attributes(attr)
  rescue 
    warn "warning: problem in db_adj(#{data})"
  end

  def adj_exit_alerts(rec)
    @alert_mgr = AlertMgr.new
    sec_id     = redis.hget "pos:#{rec[:pos_id]}", "sec_id"
    puts "adj_exit_alerts: sec_id = #{sec_id}"
    @alert_mgr.adjust_for_split("RiskMgr",sec_id,rec[:pos_id],rec[:ratio])
  end

  def stock_tkr_exists?(tkr)
    sec_id = SmTkrs.find_by_tkr(tkr) || false
  end
end

