#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"

require "rubygems"
require "ib-ruby"
require "s_m"
require "zts_ib_constants"
require 'action_view'
require 'bunny'
require "log_helper"
require 'my_config'

class EWrapperMd
  include LogHelper
  attr_accessor :channel
  attr_reader :this_broker, :sec_master

  def initialize(ib,this_broker)
    @ib = ib
    @this_broker = this_broker
    
    Zts.configure do |config|
      config.setup
    end

    progname = File.basename(__FILE__,".rb") 
    
    @sec_master = SM.instance

    amqp_factory = AmqpFactory.instance
    show_info "connection = Bunny.new( #{amqp_factory.params} )"
    connection = Bunny.new( amqp_factory.params )
    connection.start

    @channel  = connection.create_channel
  end
  
  def run
    info_subscriptions
    std_subscriptions
  end

  def report
  end
  
  def md_routing_key(std_route,ticker_id)
    market,id = sec_master.decode_ticker(ticker_id)    # IB::SECURITY_TYPES
    "#{std_route}.#{market}.#{id}"
  end
    
  def info_subscriptions
    @ib.subscribe(:Alert) { |msg| show_info "#{msg.to_human}" }
  end
  
  def std_subscriptions
    
    # market data subscriptions
    @ib.subscribe(:TickPrice, :TickSize, :TickGeneric, :TickString) { |msg|
      show_info "#{msg.class.to_s[/.*::(.*)/, 1]}(#{msg.data[:ticker_id]}) "+msg.to_human
    }
    
    @ib.subscribe(:RealTimeBar) { |msg| 
      routing_key = md_routing_key(Zts.conf.rt_bar5s, msg.data[:request_id])
      exchange = channel.topic(Zts.conf.amqp_exch_mktdata,
                               Zts.conf.amqp_exch_options)
      
      print "."
      market,sec_id = sec_master.decode_ticker(msg.data[:request_id])
      payload = msg.data[:bar].merge(mkt: market, sec_id: sec_id)
      puts "#{exchange.name}.publish(#{payload}.to_json, :routing_key => #{routing_key})"
      exchange.publish(payload.to_json, :routing_key => routing_key)

    }
  end
end
