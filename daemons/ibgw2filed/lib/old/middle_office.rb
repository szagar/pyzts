require 'singleton'
require 'log_helper'
require 'fill_struct'
require "my_config"
require "portfolio_mgr"
require "ib_redis_store"

class MiddleOffice
  include Singleton
  include LogHelper

  attr_accessor :efile, :efile_name, :booking_dir, :script_dir
  attr_accessor :store

  def initialize
    Zts.configure { |config| config.setup }
    #@efile       = open_efile
    #@efile_name  = config.execution_file
    #@booking_dir = config.dir_mo
    #@script_dir  = config.dir_scripts
    @portf_mgr   = PortfolioMgr.instance
    @store       = IbRedisStore.new
  end

  #def submit_commission(commission)
  #  efile.puts commission.to_json
  #end

  #def submit_execution(fill)
  #  efile.puts fill.to_json
  #end

  def book_execution(fill)
#    allocate(fill)
  end

  def book_executions
    booking_file = rotate_execution_file
    fork do
      exec("#{script_dir}/process_executions.rb", booking_file)
    end
  end

  def allocate(fill)
    show_info "MiddleOffice#allocate(#{fill})"
    position     = @portf_mgr.position(fill.pos_id) 
    account_name = position.account_name
    sec_id       = position.sec_id
    alloc_id = create_update_allocation(account_name, sec_id,
                                        fill.quantity, fill.price)
    create_alloc_fill(alloc_id,fill)
  rescue CannotAllocate => e
    warn e.message
  end

  def assign_commission(exec_id, amount)
    show_info "MiddleOffice#assign_commission(#{exec_id}, #{amount})"
    # add commission amount to fill by exec_id
    # add commission to position
    pos_id = store.assign_alloc_commission(exec_id, amount)
    #update_position_commission(pos_id, amount)
  end

  #####################
  private
  #####################

  def update_position_commission(pos_id, amount)
  end

  def create_update_allocation(account_name, sec_id, quantity, price)
    show_info "MiddleOffice#create_update_allocation(#{account_name}, #{sec_id}, #{quantity}, #{price})"
    @store.create_update_allocation(account_name, sec_id, quantity, price)
  end

  def create_alloc_fill(alloc_id,fill)
    @store.alloc_fill_persister(alloc_id,fill)
  end
 
  def rotate_execution_file
    efile.close
    booking_file = book_efile
    @efile = open_efile
    booking_file
  end

  def open_efile
    File.open(executions.json, "a+")
  end

  def book_efile
    File.rename(efile_name, booking_file_name)
  end

  def booking_file_name
    ts = Time.now.strftime("%Y%m%d%H%M%S")
    "#{booking_dir}/#{efile_name}.#{ts}"
  end
end
