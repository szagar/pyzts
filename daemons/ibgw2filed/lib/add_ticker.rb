#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"
require 'store_mixin'

require 'active_record'
require 'logger'
require "log_helper"
require "file_helper"
require "s_n"
require 'date_time_helper'

class SmTkrs < ActiveRecord::Base  
end
class IdxTkrs < ActiveRecord::Base  
end

class AddTicker
  include LogHelper
  include FileHelper
  include Store

  def initialize(update_db=false)
    @update_db = update_db
    Zts.configure { |config| config.setup }
    @sequencer = SN.instance

    today = DateTimeHelper::integer_date
    data_dir = "/Users/szagar/zts/log"
    (@fh_log   = File.open("#{data_dir}/#{today}_AddTicker.csv", 'a')).sync = true
 
    if update_db 
      logname = File.dirname(__FILE__) + '/../..' + '/log/' + File.basename(__FILE__, ".rb")+'_AR.log'
      show_info "AR logname=#{logname}"
      ActiveRecord::Base.logger = Logger.new(logname)
      ActiveRecord::Base.configurations = YAML::load(IO.read(ENV["ZTS_HOME"]+'/etc/database.yml'))
      ActiveRecord::Base.establish_connection(ENV["ZTS_ENV"].to_sym)
    end
  end

  def cleanup
    ActiveRecord::Base.remove_connection()
  end

  def run(data)
    puts "run(#{data})"
    rec = form_record(data)
    return unless rec
    add_tkr(rec)
  end

  #################
  private
  #################

  def form_record(data)
    return false unless valid_str?(data[:tkr])
    tkr      = data[:tkr]
    sec_id   = "tbd"
    ib_tkr   = data[:ib_tkr]   || tkr
    exchange = data[:exchange] || "tbd"
    desc     = data[:desc]     || "tbd"
    { tkr:      tkr,
      sec_id:   sec_id,
      ib_tkr:   ib_tkr,
      exchange: exchange,
      desc:     desc
    }
  end

  def valid_str?(s)
    s =~ /^\w+/
  end

  def add_tkr(rec)
    puts "add_tkr: rec=#{rec}"
    if @update_db && stock_tkr_exists?(rec[:tkr])
      warn "Stock Symbol Exists: #{rec[:tkr]}/#{rec[:exchange]} #{rec[:desc]}"
    else
      if redis_tkr_exists?(rec[:tkr])
        warn "#{rec[:tkr]} already in redis db"
        return
      end

      show_action "Add Stock Symbol: #{rec[:tkr]}/#{rec[:exchange]} #{rec[:desc]}"
      log_command(rec)
      rec[:sec_id] = @sequencer.next_sec_id
      db_add(rec) if @update_db
      update_redis(rec)
    end
  end

  def log_command(rec)
    @fh_log.write "./run_add_ticker.rb #{rec[:tkr]} \"#{rec[:desc]}\"\n"
  end

  def update_redis(rec)
    redis_md.set "tkrs:#{rec[:tkr]}", rec[:sec_id]
    redis_md.hset "sec:#{rec[:sec_id]}", "tkr", rec[:tkr]
    redis_md.hset "sec:#{rec[:sec_id]}", "ib_tkr", rec[:ib_tkr] if rec[:ib_tkr]
    redis_md.hset "sec:#{rec[:sec_id]}", "exchange", rec[:exchange]
    redis_md.hset "sec:#{rec[:sec_id]}", "desc", rec[:desc]
  end

  def redis_tkr_exists?(tkr)
    return (redis_md.get "tkrs:#{tkr}") ? true : false
  end

  def stock_tkr_exists?(tkr)
    sec_id = SmTkrs.find_by_tkr(tkr) || false
  end

  def db_add(rec)
    puts "db_add(#{rec})"
    SmTkrs.create(sec_id: rec[:sec_id], tkr: rec[:tkr], ib_tkr: rec[:ib_tkr],
                  desc: rec[:desc], exchange: rec[:exchange])      
  rescue ActiveRecord::RecordNotUnique
    warn "warning: duplicate entry in sm_tkrs (tkr:#{rec[:tkr]})"
  end
end
