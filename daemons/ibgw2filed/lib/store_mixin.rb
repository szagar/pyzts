# $: << "#{ENV['ZTS_HOME']}/lib"
# require "s_n"
require "redis_factory"


module Store
  #def initialize
  #  $redis    = false
  #  $redis_md = false
  #end

  def whoami
    self.class.to_s
  end

  def dbg(str)
    redis.append 'dbg', str
  end

  def exists?(id)
    (redis.keys pk(id)).count > 0
  end

  def create(params)
    show_info "Store#create(#{params})"
    id = params[id_str] = next_id
    params.each do |k,v|
      debug "#{whoami}#create: redis.hset #{pk(id)}, #{k} ,#{v}"
      redis.hset pk(id), k ,v
    end
    id
  end

  def getter(id, field)
    #puts "\nredis.hget #{pk(id)}, #{field}"
    redis.hget pk(id), field
  end

  def setter(id, field, value)
    redis.hset pk(id), field, value
  end

  def dump(id)
    redis.hgetall pk(id)
  end

  def members(id)
    puts "Store#members: redis.hkeys #{pk(id)}"
    redis.hkeys pk(id)
  end

  #######
  private
  #######

  def redis_factory
    @redis_factory ||= RedisFactory.instance
  end

  def redis
    $redis ||= redis_factory.client
  end

  def redis_md
    $redis_md ||= redis_factory.client("mkt_data")
  end

  def id_str
    "#{self.class.to_s.chomp("Store").downcase}_id"
  end

  def next_id
    seq = sequencer rescue SN.instance
    (seq || SN.instance).send("next_#{id_str}")
  end

  def pk(id)
    "#{self.class.to_s.chomp("Store").downcase}:#{id}"
  end

end
