#$: << "#{ENV['ZTS_HOME']}/etc"
require "singleton"
require "log_helper"
require "store_mixin"

class PositionStore # < RedisStore
  include Singleton
  include LogHelper
  include Store
  
  attr_reader :sequencer

  def initialize
    #show_info "PositionStore#initialize"
    @sequencer = SN.instance
    super
  end

  def add_commissions(pos_id, amount)
    comm = (getter(pos_id, "commissions") || 0.0).to_f
    new_comm = comm + amount
    redis.hset pk(pos_id), "commissions", new_comm
    new_comm
  end

  #######
  private
  #######

  def next_id
    sequencer.next_pos_id
  end

  def pk(name)
    "pos:#{name}"
  end

  def id_str
    "pos_id"
  end
end
