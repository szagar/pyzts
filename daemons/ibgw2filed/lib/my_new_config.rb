module Zts
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  class Configuration
    attr_accessor :redis_host, :redis_port, :redis_database
    attr_accessor :zts_env
    attr_accessor :thishost

    def initialize
      @zts_env    = ENV['ZTS_ENV']
      @thishost   = `hostname`.chomp[/(.*)\..*/,1]

      env_specific(@zts_env)
      host_specific(@this_host)
    end

    def env_specific(env)
      @redis_port = "6379"

      case env
      when "development"
        @redis_host = "localhost"
        @redis_database = "0"
      when "test"
        @redis_host = "localhost"
        @redis_database = "1"
      when "production"
        @redis_host = 'example.com'
        @redis_database = "9"
      end
    end

    def host_specific(host)
      case host
      when "macdaddy" 
        @redis_database = "2"
      end
    end
  end
end

Zts.configure do |config|
  config.redis_host = 'prod1.com'
end

puts "redis_host    : #{Zts.configuration.redis_host}"
puts "redis_port    : #{Zts.configuration.redis_port}"
puts "redis_database: #{Zts.configuration.redis_database}"
puts "zts_env       : #{Zts.configuration.zts_env}"
puts "thishost      : #{Zts.configuration.thishost}"
