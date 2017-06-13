require "amqp"
require "my_config"
require "singleton"

class AmqpFactory
  include Singleton

  def initialize
    Zts.configure do |config|
      config.setup
    end
  end

  def params
    { host:  Zts.conf.amqp_host,
      vhost: Zts.conf.amqp_vhost,
      user:  Zts.conf.amqp_user,
      pass:  Zts.conf.amqp_pswd,
      heartbeat_interval: 10
    }
  end

  def md_params
    { host:  Zts.conf.amqp_md_host,
      vhost: Zts.conf.amqp_md_vhost,
      user:  Zts.conf.amqp_md_user,
      pass:  Zts.conf.amqp_md_pswd,
      heartbeat_interval: Zts.conf.amqp_md_hb_int
    }
    #{ host:  "appserver01.local",
    #  vhost: "/zts_prod",
    #  user:  "zts",
    #  pass:  "zts123",
    #  heartbeat_interval: 10
    #}
  end

  def channel
      puts "==>@connection ||= AMQP.connect(#{params})"
      @connection ||= AMQP.connect(params)
      @channel    ||= AMQP::Channel.new(@connection)
      [@connection,@channel]
  end

  def md_channel
      puts "==>@md_connection ||= AMQP.connect(#{md_params})"
      @md_connection ||= AMQP.connect(md_params)
      @md_channel    ||= AMQP::Channel.new(@md_connection)
      [@md_connection,@md_channel]
  end
end
