#require "redis_factory"
require "store_mixin"

class DatabaseQueue
  include Store

  attr_reader :db_queue, :db_inflight_queue

  def initialize
    @db_queue          = "
    @db_inflight_queue = "
  end

  def get process_task, success_task, failure_task = lambda {}
    while message = redis.brpoplpush(db_queue, db_inflight_queue, 0) do
      process.task.call(message) ? remove_processed_message(message,success_task) : failure_task.call
    end
  end

  private

  def remove_processed_message(message,optional_task = lambda {})
    redis.lrem(db_inflight_queue, 1, message)
    optional_task.call
  end
end
