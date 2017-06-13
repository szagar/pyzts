require "redis_factory"

module TransactionLog
  class Base
    attr_reader :client_id, :topic, :redis, :next_id

    def initialize(client_id,options)
      @client_id   = client_id
      @topic       = options.fetch(:topic)       { "0" }
      @redis       = RedisFactory.instance.client
      #@log         = options.fetch(:log_store)   { TransactionLog::RedisLog.new(@topic) }
    end

    def last
      redis.llen "tlog:topic:#{topic}"
    end

    def sequence_no
      (redis.get "tlog:client_ptr:#{@topic}:#{client_id}").to_i
    end

    def ack
      redis.incr "tlog:client_ptr:#{@topic}:#{client_id}"
    end

    def write_to_log(payload)
      #redis...... "tlog:topic:#{topic}", next_id, payload
      redis.rpush "tlog:topic:#{topic}", payload
      write_to_subscribers(payload)
    end

    def write_to_consumers(payload)
      consumers.each { |s| redus.rpush s, payload }
    end

    def get_from_log(seq_no)
      redis.lindex "tlog:topic:#{topic}", seq_no
    end

    def pending_msg_count
      last.to_i - sequence_no.to_i
    end

    def initialize_log
      redis.set "tlog:client_ptr:#{@topic}:#{client_id}", 0
    end

    def cleanup_from_test_script_carefully
      redis.del "tlog:topic:#{topic}"
      redis.del "tlog:client_ptr:#{@topic}:#{client_id}"
    end
  end

  class Producer < Base
    def initialize(client_id, options={})
      super
    end

    def publish(payload)
      write_to_log(payload)
    end

    def <<(payload)
      publish payload
    end
  end

  class Consumer < Base
    def initialize(client_id,options={})
      super
      sequence_no || initialize_log
    end

    def consume(seq_no = sequence_no)
      get_from_log(seq_no)
    end

    #def ack
    #  @log.ack
    #end
  end

  class LogMessage
    def initialize
    end

    def topic_messsage(topic,msg)
    end
  end
end
