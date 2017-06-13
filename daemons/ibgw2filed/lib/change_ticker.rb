#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"
require 'store_mixin'

require 'active_record'
require 'logger'
require "log_helper"
require "file_helper"


class SmTkrs < ActiveRecord::Base  
end
class IdxTkrs < ActiveRecord::Base  
end

class ChangeTicker
  include LogHelper
  include FileHelper
  include Store

  def initialize
    Zts.configure { |config| config.setup }
    logname = File.dirname(__FILE__) + '/..' + '/log/' + File.basename(__FILE__, ".rb")+'_AR.log'
    show_info "AR logname=#{logname}"
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
    warn "Could not change ticker: #{data[:old_tkr]}" unless rec
    change_tkr(rec) if rec
  end

  #################
  private
  #################

  def form_record(data)
    puts "form_record(#{data})"
    return false unless valid_str?(data[:old_tkr])
    return false unless valid_str?(data[:new_tkr])
    return false unless (sec_id = lookup_sec_id(data[:old_tkr]))
    ib_tkr   = (data[:ib_tkr] || data[:new_tkr])
    { old_tkr:  data[:old_tkr],
      new_tkr:  data[:new_tkr],
      sec_id:   sec_id,
      ib_tkr:   ib_tkr,
    }
  end

  def valid_str?(s)
    s =~ /^\w+/
  end

  def change_tkr(rec)
    puts "change_tkr: rec=#{rec}"
    show_action "Change Stock Symbol for #{rec[:sec_id]} from #{rec[:old_tkr]} to #{rec[:new_tkr]}"
    rec.merge!(sec_id: rec[:sec_id])
    rec.merge!(ib_tkr: rec[:ib_tkr])
    db_change(rec)
    update_redis(rec)
  end

  def update_redis(rec)
    puts "redis_md.set tkrs:#{rec[:new_tkr]}, #{rec[:sec_id]}"
    puts "redis_md.hset sec:#{rec[:sec_id]}, tkr, #{rec[:new_tkr]}"
    puts "redis_md.hset sec:#{rec[:sec_id]}, ib_tkr, #{rec[:ib_tkr]} if #{rec[:ib_tkr]}"

    redis_md.set "tkrs:#{rec[:new_tkr]}", rec[:sec_id]
    redis_md.hset "sec:#{rec[:sec_id]}", "tkr", rec[:new_tkr]
    redis_md.hset "sec:#{rec[:sec_id]}", "ib_tkr", rec[:ib_tkr] if rec[:ib_tkr]

    puts "redis_md.del tkrs:#{rec[:old_tkr]}"
    redis_md.del  "tkrs:#{rec[:old_tkr]}"
  end

  def lookup_sec_id(tkr)
    puts "lookup_sec_id(#{tkr})"
    SmTkrs.find_by_tkr(tkr)[:sec_id] 
  rescue
    false
  end

  def db_change(data)
    rec = SmTkrs.find_by_sec_id(data[:sec_id])
    rec.update_attributes(tkr: data[:new_tkr], ib_tkr: data[:ib_tkr])
  rescue 
    warn "warning: problem in db_change(#{data})"
  end
end
