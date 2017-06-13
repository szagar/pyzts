require "log_helper"

class RedisStore
  include LogHelper

  #attr_reader :redis

  def initialize(*args)
    #show_info "RedisStore#initialize"
    $redis ||= RedisFactory2.new.client
  end

  def store
    $redis
  end
end
