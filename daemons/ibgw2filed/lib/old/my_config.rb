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
    attr_accessor :this_host

    def initialize
      setup
    end

    def setup
      @zts_env   = ENV['ZTS_ENV']
      @this_host = `hostname`.chomp[/(.*)\..*/,1]
      env_specific(@zts_env)
      host4env_specific(@zts_env,@this_host)
    end

    private

    def env_specific(env)
      @redis_port = "6379"

      case env
      when "development"
        @redis_host = "localhost"
        @redis_database = "0"
      when "test"
        @redis_host = "localhost2"
        @redis_database = "1"
      when "production"
        @redis_host = 'example.com'
        @redis_database = "9"
      end
    end

    def host4env_specific(env,host)
      case env
      when "development"
        case host
        when "macdaddy" 
          @redis_database = "2"
        end
      end
    end
  end
end
