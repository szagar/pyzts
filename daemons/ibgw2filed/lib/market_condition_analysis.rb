$: << "#{ENV['ZTS_HOME']}/etc"

require "singleton"

require "store_mixin"
require "log_helper"

class MarketConditionAnalysis
  include Singleton  
  include LogHelper  
  include Store  

  def initialize
  end

  def attributes
    redis.hgetall "mca:latest"
  end

  def set(k,v)
    redis.hset "mca:latest", k, v
  end

  #######
  private
  #######

end
