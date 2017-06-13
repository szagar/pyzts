#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"

require "redis_factory"

module DbPositionQueue
  Queue         = "db_queue"
  InflightQueue = "db_inflight_queue"

  class Producer
    def initialize
    end

    def push(message)
      redis.rpush Queue, message
    end
  end

  class Consumer
    def initialize
    end
  
    def run
      while message = redis.brpoplpush(Queue, InflightQueue, 0) do
        db_insert(message) ? db_success(message) : db_failure(message)
      end
    end

    private

    def db_insert(message)
      case message[:command]
      when "create_position"
        valid_integer?(message[:pos_id]) ? create_position(message[:pos_id],message[:data]) : invalid_pos_id(message)
      when "update_position"
        valid_integer?(message[:pos_id]) ? update_position(message[:pos_id],message[:data]) : invalid_pos_id(message)
      when "close_position"
        valid_integer?(message[:pos_id]) ? close_position(message[:pos_id]) : invalid_pos_id(message)
      else
        invalid_command(message)
      end
    end

    def remove_processed_message(message)
      redis.lrem(inflight_queue, 1, message)
    end

    def db_success(message)
      remove_processed_message(message)
    end

    def db_failure(message)
      warn "failed to load: #{message}"
      warn "check in-flight queue: #{inflight_queue}"
    end

    def create_position(pos_id,data)
    end

    def update_position(pos_id,data)
    end
  
    def close_position(pos_id)
    end

    def valid_integer?(number)
      number.to_s =~ /^\d+$/
    end

    def invalid_pos_id(message)
    end
  end

  class Message
    def initialize(command,params)
    end
  end
end

puts "here"
redis = RedisFactory.instance.client
while (msg = redis.blpop "db_queue", 0)
  puts msg
end
