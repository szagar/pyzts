#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'order_struct'
require "zts_config"
require "amqp"
require "json"
require "e_wrapper_dev"


class MyIb

  def initialize
  end
  
  def watch_for_new_orders(channel)
    queue    = channel.queue("orders", auto_delete: true)
    queue.subscribe do |payload|
      puts payload
    end
      
#    routing_key = "#{ZtsApp::Config::ROUTE_KEY[:order_flow][:order]}.#{this_broker}"
#    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:order_flow][:name],
#                             ZtsApp::Config::EXCHANGE[:core][:options])
#    
#    set_hdr "setup ->(#{exchange.name}/#{routing_key})"
#    channel.queue("", :auto_delete => true)
#           .bind(exchange, :routing_key => routing_key)
#           .subscribe do |headers, payload|

#    exchange = channel.topic('orders', {:durable => true, :auto_delete => true})
#    puts "setup ->(#{exchange.name}/orders)"
#    channel.queue('orders').bind(exchange, :routing_key => "orders").subscribe do |headers, payload|
#      puts payload
#    end
  end
  
  def watch_for_md_requests(channel)
    queue_name = routing_key = ZtsApp::Config::ROUTE_KEY[:request][:bar5s]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                             ZtsApp::Config::EXCHANGE[:market][:options])
    puts "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      puts payload
    end
  end
  
  def watch_for_account_requests(channel)
    queue_name = routing_key = ZtsApp::Config::ROUTE_KEY[:request][:acctData]
    exchange = channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                             ZtsApp::Config::EXCHANGE[:market][:options])
    puts "setup ->(#{exchange.name}/#{routing_key})"
    channel.queue(queue_name, :auto_delete => true)
           .bind(exchange, :routing_key => routing_key)
           .subscribe do |headers, payload|
      puts "query_account_data"
    end
  end
  
  def run
    t1 = Thread.new { EventMachine.run }
    puts "start EM"
    EventMachine.next_tick do
      #connection = AMQP.connect(connection_settings)
      connection = AMQP.connect(host: ZtsApp::Config::AMQP[:host])
      
      channel  = AMQP::Channel.new(connection)
      exchange = channel.direct("")

      Fiber.new {
        ew=EWrapperDev.new(@ib,self)
        ew.run
      }.resume

      show_stopper = Proc.new {
        #debug "show stopper *************************************"
        connection.close { EventMachine.stop }
      }
      
      watch_for_new_orders(channel)
     # watch_for_md_requests(channel) if mkt_data_server
     # watch_for_md_unrequests(channel) if mkt_data_server
      watch_for_account_requests(channel)
      
      Signal.trap("INT") { puts "interrupted caught in MyIb"; connection.close { EventMachine.stop } }
    end
    t1.join
  end
end

my_ib = MyIb.new
my_ib.run

