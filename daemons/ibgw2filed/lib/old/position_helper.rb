require_relative 'old/position'
require 'redis_position'

module PositionHelper
  extend self 

  def instantiate_pos(pos_id)
    pos = Position.new
    pos.get(pos_id)
    pos
  end

  def update_attribute(pos_id, attrib, value)
    parms = {}
    parms[attrib] = value
    puts "RedisPosition.set(#{pos_id}, #{parms})"
    RedisPosition.set(pos_id, parms)
  end
end
