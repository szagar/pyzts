$: << "#{ENV['ZTS_HOME']}/lib"
require "redis"
require "s_n"

module EntryStore
  extend self
  
  def whoami
    "EntryStore"
  end

  def exists?(id)
    redis.keys pk(id)
  end

  def create(params)
    id = next_id
    params.each do |k,v|
      redis.hset pk(id), k ,v
    end
    id
  end

  def members(id)
    @redis.hkeys pk(id)
  end

  def set_redis(redis)
    @redis = redis
    SN.set_redis(redis)
  end

  def getter(id, field)
    puts "\nEntryStore#getter(#{id}, #{field})"
    redis.hget pk(id), field
  end

  def setter(id, field, value)
    redis.hset pk(id), field, value
  end

  def dump(id)
    redis.hgetall pk(id)
  end

  #######
  private
  #######

  def redis
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end

  def next_id
    SN.next_entry_id
  end

  def pk(id)
    "entry:#{id}"
  end

end
