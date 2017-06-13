#!/usr/bin/env ruby
# encoding: utf-8
$: << "#{ENV['ZTS_HOME']}/lib"

require "active_record"
require "my_config"
require "log_helper"
require "portfolio_mgr"
require "ib_redis_store"
require "date_time_helper"
require "logger"

class DbFills < ActiveRecord::Base
end
class DbPositions < ActiveRecord::Base
end
class DbPositionTags < ActiveRecord::Base
end

class AllocationExecution
  include LogHelper

  attr_accessor :store

  def initialize
    Zts.configure { |config| config.setup }
    @portf_mgr = PortfolioMgr.instance
    @store     = IbRedisStore.new
    db_initialize

  end

  def allocation_executions
  end

  def book_em
    while(exec = execution_to_book) do
      load_n_save_position(exec[:pos_id])
      save_execution(exec)
      update_position(exec)
    end
  end

  #############
  private
  #############

  def execution_to_book
    return unless (execution = store.execution_to_book)
    { pos_id:     execution['pos_id'],
      #sec_id:     execution['sec_id'],
      exec_id:    execution['exec_id'],
      price:      execution['price'],
      avg_price:  execution['avg_price'],
      quantity:   execution['quantity'],
      commission: execution['commissions'],
      action:     execution['action'],
      #action2:    execution['action2'],
      broker:     execution['broker'],
      account:    execution['account_name'],
      ref_id:     execution['local_id'],
    }
  end

  def load_n_save_position(pos_id)
    puts "load_n_save_position(#{pos_id})"
    return if position_saved?(pos_id)
    pos_data = load_position(pos_id)
    save_position(pos_data)
  end

  def position_saved?(pos_id)
    puts "position_saved?(#{pos_id})"
    puts "DbPositions.where(pos_id: #{pos_id}).first"
    DbPositions.where(pos_id: pos_id).first
  end

  def load_position(pos_id)
    puts "load_position(#{pos_id})"
    @portf_mgr.position(pos_id).db_parms
  end

  def update_position(exec)
    puts "update_position(#{exec})"
    pos = DbPositions.find_by_pos_id(exec[:pos_id])
    side_factor = (exec[:action] == "buy") ? 1 : -1
    puts "new_quantity = #{pos.quantity} + #{side_factor} * #{exec[:quantity]}"
    new_quantity = pos.quantity + side_factor * exec[:quantity].to_f
    position_qty = pos.position_qty
    attribs = {quantity: new_quantity}
    case pos.side
    when "long"
      puts "position_qty = #{position_qty} + #{exec[:quantity]} if #{exec[:action]} == buy"
      (position_qty = position_qty + exec[:quantity].to_f) if exec[:action] == "buy"
      attribs.merge!(avg_entry_px: calc_entry_px(pos,exec)) if exec[:action] == "buy"
      attribs.merge!(avg_exit_px: calc_exit_px(pos,exec))   if exec[:action] == "sell"
    when "short"
      position_qty += exec[:quantity] if exec[:action] == "sell"
      attribs.merge!(avg_entry_px: calc_entry_px(pos,exec)) if exec[:action] == "sell"
      attribs.merge!(avg_exit_px: calc_exit_px(pos,exec))   if exec[:action] == "buy"
    end
    attribs.merge!(position_qty: position_qty)
    pos.update_attributes(attribs)
    pos.save
    close_position(pos) if ( pos.side == "long" && pos.quantity <= 0) ||
                                   ( pos.side == "short" && pos.quantity >= 0)
  end

  def calc_entry_px(pos,exec)
    puts "(#{pos.avg_entry_px} * #{pos.quantity} + #{exec[:price]} * #{exec[:quantity]}) / (#{pos.quantity} + #{exec[:quantity]})"
    (pos.avg_entry_px.to_f * pos.quantity.to_f + exec[:price].to_f * exec[:quantity].to_f) /
    (pos.quantity.to_f + exec[:quantity].to_f)

  end

  def calc_exit_px(pos,exec)
    (pos.avg_exit_px.to_f * pos.quantity.to_f + exec[:price].to_f * exec[:quantity].to_f) /
    (pos.quantity.to_f + exec[:quantity].to_f)
  rescue
    warn "Failed to calc exit price for pos:#{pos.pos_id}"
    0.0
  end

  def close_position(pos)
    pos.status = "closed"
    pos.save
    calc_pos_metrics(pos)
  end

  def calc_pos_metrics(pos)
    pos.realized = (pos.avg_exit_px - pos.avg_entry_px) * pos.position_qty if pos.side == "long"
    pos.realized = (pos.avg_entry_px - pos.avg_exit_px) * pos.position_qty if pos.side == "sell"
    pos.unrealized = 0
    pos.save
    pos.r_multiple = pos.realized / pos.init_risk_position #rescue 0
    pos.returnP = (pos.avg_exit_px - pos.avg_entry_px) / pos.avg_entry_px * 100.0
    pos.returnD = pos.realized
    pos.days = DateTimeHelper::days(pos.trade_date,pos.closed_date)
    pos.save
  end

  def save_position(pos_data)
    save_tags(pos_data)
    DbPositions.create(pos_data)
  end

  def save_tags(pos_data)
    tags = (pos_data.fetch(:tags) {""}).split ","
    pos_data.delete(:tags)
    tags.each { |tag| save_tag(pos_data[:pos_id],tag) }
  end

  def save_tag(pos_id,tag,value=nil)
    DbPositionTags.create(pos_id: pos_id, tag: tag, value: value)
  end

  def save_execution(exec)
    DbFills.create(exec)
  end

  def db_initialize
    ar_logname = Zts.conf.dir_log + "/" + File.basename(__FILE__, ".rb")+'.log'
    puts "ar_logname=#{ar_logname}"
    ActiveRecord::Base.logger = Logger.new(ar_logname)
    ActiveRecord::Base.configurations = YAML::load(IO.read(Zts.conf.dir_config + "/database.yml"))
    ActiveRecord::Base.establish_connection('development')
    ar_logger = Logger.new(ar_logname)
    ar_logger.datetime_format = '%Y-%m-%d %H:%M:%S'
    ar_logger.level = Logger::INFO   #  DEBUG INFO WARN ERROR FATAL
  end
end

ae = AllocationExecution.new
ae.book_em
