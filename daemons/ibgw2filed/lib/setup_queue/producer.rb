require_relative "../store_mixin"
require_relative "message"

module SetupQueue
  def self.queue
    @@queue
  end

  def self.inflight_queue
    @@inflight_queue
  end

  def self.set_queue(q)
    @@queue = q
    @@inflight_queue = q + "_inflight"
  end

  class Producer
    include Store

    def initialize(queue)
      SetupQueue::set_queue(queue)
    end

    def push(message)
      redis.rpush SetupQueue::queue, message.to_json
    end
  end
end
