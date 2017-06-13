$: << "#{ENV['ZTS_HOME']}/etc"
require 'bunny'

class AmqpSync
  attr_reader :exchange

  def initialize
    conn = Bunny.new("amqp://guest:guest@appserver01.local")
    conn.start
    channel  = conn.create_channel
    @exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name],
                               ZtsApp::Config::EXCHANGE[:core][:options])
  end

  def publish(msg, *options)
    exchange.publish(msg, options[0])
  end

  def name
    exchange.name
  end
end
