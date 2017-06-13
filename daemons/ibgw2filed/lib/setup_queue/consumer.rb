#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib2"

#require "active_record"
#require "logger"
#require "log_helper"
require "store_mixin"
#require "s_m"
require "setup_queue/message"

#class Positions      < ActiveRecord::Base; end
#class PositionTags   < ActiveRecord::Base; end
#class McaData        < ActiveRecord::Base; end
#class Executions     < ActiveRecord::Base; end
##class BrokerAccounts < ActiveRecord::Base; end
#class Accounts       < ActiveRecord::Base; end
#class IbAccountData  < ActiveRecord::Base; end
#class SmTkrs         < ActiveRecord::Base; end
#class SmPrices       < ActiveRecord::Base; end

module SetupQueue
  def self.queue;          @@queue;          end
  def self.inflight_queue; @@inflight_queue; end
  def self.set_queue(q);   @@queue = q
                           @@inflight_queue = q + "_inflight"; end
  class Consumer
    include LogHelper
    include Store
    attr_reader :ibAccountDataFields, :accountDataFields
    attr_reader :sec_master

    def initialize(queue)
      #Zts.configure { |config| config.setup }
      SetupQueue::set_queue(queue)
    end
  
    def pop
      json_msg = redis.lpop(SetupQueue::queue)
      return false unless json_msg
puts "json_msg=#{json_msg}"
      command, params = SetupQueue::Message.decode(json_msg)
puts "command=#{command}"
puts "params=#{params}"
      params
    end

    def run
      while ( json_msg = redis.blpop(SetupQueue::queue, 0)[1])
        redis.rpush SetupQueue::inflight_queue, json_msg
        command, params = SetupQueue::Message.decode(json_msg)
        puts "command: #{command}  params: #{params}"
        (self.send command, params) ? submit_success(json_msg) : submit_failure(json_msg)
      end
    end

    def test_new_setup(data)
      new_setup(data)
    end

    private

    def nop(data)
      warn "SetupQueue::Consumer#nop"
    end

    def new_setup(exchange,setup)
      routing_key = Zts.conf.rt_setups
      transcript = StringIO.new
      if setup.valid?(transcript)
        puts "<-(#{exchange.name}/#{routing_key}) "\
                 "#{setup[:setup_src]} #{setup[:ticker]} #{setup[:side]} "\
                 "entry stop: #{setup[:entry_stop_price]} ="\
                 "#{setup[:trailing_stop_type]}= "\
                 "support:#{setup.attributes.fetch('support'){'NA'}} "\
                 "trade_type:#{setup[:trade_type]} "
        exchange.publish(setup.attributes.to_json, :routing_key => routing_key)
      else
        warn transcript.string
        false
      end
    end

    def remove_processed_message(message)
      redis.lrem(InflightQueue, 1, message)
    end

    def submit_success(message)
      remove_processed_message(message)
    end

    def submit_failure(message="")
      warn "failed to load: #{message}"
      warn "check in-flight queue: #{InflightQueue}"
    end

  end
end
