require "amqp"
require "my_config"

class AmqpFactory
  def initialize(env=ENV['ZTS_ENV'])
    Zts.configure(env) { |config| config.setup }
  end

  def params
    { host:  Zts.conf.amqp_host,
      vhost: Zts.conf.amqp_vhost,
      user:  Zts.conf.amqp_user,
      pass:  Zts.conf.amqp_pswd
    }
  end

  def md_params
    #{ host:  Zts.conf.amqp_md_host,
    #  vhost: Zts.conf.amqp_md_vhost,
    #  user:  Zts.conf.amqp_md_user,
    #  pass:  Zts.conf.amqp_md_pswd
    #}
    { host:  "appserver01.local",
      vhost: "/zts_prod",
      user:  "zts",
      pass:  "zts123"
    }
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
