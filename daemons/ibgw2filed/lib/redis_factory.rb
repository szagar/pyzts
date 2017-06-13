require "redis"
require "my_config"
require "log_helper"
require "singleton"

class RedisFactory
  include LogHelper
  include Singleton

  attr_reader :host, :port

  def initialize
    #debug "RedisFactory#initialize"
    Zts.configure do |config|
      config.setup
    end
  end

  def client(ctype="std")
    #debug "RedisFactory#client(#{ctype})"
    if ctype == "mkt_data"
      host = Zts.conf.redis_mktdata_host
      port = Zts.conf.redis_mktdata_port
      db   = Zts.conf.redis_mktdata_database
      url = "redis://#{host}:#{port}/#{db}"
      #puts "RedisFactory#client url=#{url}"
      @mkt_data ||= connect(url, :timeout => 0.7)
    else
      host = Zts.conf.redis_host
      port = Zts.conf.redis_port
      db   = Zts.conf.redis_database
      url = "redis://#{host}:#{port}/#{db}"
      @std ||= connect(url, :timeout => 0.7)
    end
  end

  #def production
  #  @redis.select 9
  #end
  ###########
  private
  ###########

  #def connect(host,port,db=0)
  def connect(url,options={})
=begin
    puts "Redis.new host: #{host}, port: #{port}  => database: #{Zts.conf.redis_database}"
    puts "Redis.new host: #{host}, port: #{port}, timeout: 10.0"
    @r     ||= Redis.new host: host, port: port, timeout: 10.0
    @redis ||= Redis::Retry.new(:tries => 3, :wait => 5, :redis => @r)
    @redis.select db
    @redis
=end
=begin
    r     ||= Redis.new host: host, port: port
    r.select db
    r
=end
    options.merge!(:url => url)
    #debug "Redis.connect(#{options})"
    r = Redis.connect(options)
    Redis::Retry.new(:tries => 3, :wait => 5, :redis => r)
  end
end

class Redis
  class Retry
    attr_accessor :tries
    attr_accessor :wait

    def initialize(options = {})
      @tries = options[:tries] || 3
      @wait  = options[:wait]  || 2
      @redis = options[:redis]
    end

    # Ruby defines a now deprecated type method so we need to override it here
    # since it will never hit method_missing.
    def type(key)
      method_missing(:type, key)
    end

    def method_missing(command, *args, &block)
      try = 1
      while try <= @tries
        begin
          # Dispatch the command to Redis
          return @redis.send(command, *args, &block)
        rescue Errno::ECONNREFUSED
          try += 1
          puts "Redis::Retry: try=#{try}/#{@tries}"
          sleep @wait
        rescue =>e
          warn "Redis problem .........."
          warn e.message
        end
      end

      # Ran out of retries
      raise Errno::ECONNREFUSED
    end
  end
end
