#require "redis_factory2"
require "store_mixin"
require "db_data_queue/message"

module DbDataQueue
  Queue         = "queue:db"
  InflightQueue = "queue:db:inflight"

  class Producer
    include Store

    #attr_reader :redis

    def initialize
      #@redis = RedisFactory2.new.client
    end

    def push(message)
      #command = "update_position_test"
      #msg = {command: command, data: {trailing_stop_type: "atr", pos_id: "98"} }
      #puts "redis.rpush #{Queue}, #{msg}.to_json"
      #redis.rpush Queue, msg.to_json

      puts "redis.rpush #{Queue}, #{message.hash_msg}.json_msg}"
      redis.rpush Queue, message.json_msg

      #msg = {command: command, data: {trailing_stop_type: "atr", pos_id: "99"} }
      #puts "redis.rpush #{Queue}, #{msg}.to_json"
      #redis.rpush Queue, msg.to_json
    end
  end
end
