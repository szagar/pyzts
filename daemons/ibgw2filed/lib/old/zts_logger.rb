require 'singleton'
require 'amqp'

class ZtsLogger
  include Singleton
  
  attr_accessor :exchange, :proc
  
  def set_proc_name(proc="NA")
    @proc=proc
  end
  
  def amqp_config2(exchange)
    @exchange = exchange
  end
  
  def amqp_config(channel)
#    @exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], ZtsApp::Config::EXCHANGE[:core][:options])
#    @exchange = channel.send( ZtsApp::Config::EXCHANGE[:log][:type], 
#                              ZtsApp::Config::EXCHANGE[:log][:name], 
#                              ZtsApp::Config::EXCHANGE[:log][:options])
    @exchange = channel.topic( ZtsApp::Config::EXCHANGE[:log][:name], 
                              ZtsApp::Config::EXCHANGE[:log][:options])

end
  
  def test_string
    "TESTING 123..."
  end
  
  def ts
    today = Time.now.strftime("%Y%m%d-%H:%M:%S.%L")
  end
  
  def talk(msg)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:log][:voice]}.#{proc}"
    exchange.publish("#{proc} #{msg}", :routing_key => routing_key)
  end
  
  def warn(msg,label=proc)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:log][:warn]}.#{proc}"
    $stderr.puts "#{ts} [WRN][#{proc}] #{msg}"
    exchange.publish("#{ts} [WRN][#{proc}] #{msg}", :routing_key => routing_key)      
  end
  
  def info(msg,label=proc)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:log][:info]}.#{proc}"
    exchange.publish("#{ts} [INF][#{label}] #{msg}", :routing_key => routing_key)      
  end
  
  def data(msg,label=proc)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:log][:data]}.#{proc}"
    exchange.publish("#{ts} [DTA][#{label}] #{msg}", :routing_key => routing_key)      
  end

  def debug(msg,label=proc)
    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:log][:debug]}.#{proc}"
    exchange.publish("#{ts} [DBG][#{label}] #{msg}", :routing_key => routing_key)      
  end
end
