$: << "#{ENV['ZTS_HOME']}/lib"
require "redis"
require "s_n"

module AlertStore
  extend self
  
  def whoami
    "AlertStore"
  end

  def exists?(id)
    redis.keys pk(id)
  end

  def create(params)
    id = params['alert_id'] = next_id
    params.each do |k,v|
      redis.hset pk(id), k ,v
    end
    id
  end

  def set_redis(redis)
    @redis = redis
    SN.set_redis(redis)
  end

  def getter(id, field)
    redis.hget pk(id), field
  end

  def setter(id, field, value)
    redis.hset pk(id), field, value
  end

  def dump(id)
    r = redis.hgetall pk(id)
  end

  #######
  private
  #######

  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end

  def next_id
    SN.next_alert_id
  end

  def pk(id)
    "alert:#{id}"
  end

end
