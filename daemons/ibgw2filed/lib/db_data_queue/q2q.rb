#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"

require "logger"
require "log_helper"
require "store_mixin"


Queue         = "queue:db"
InflightQueue = "queue:db:inflight"

include LogHelper
include Store

Zts.configure { |config| config.setup }

#i = 0
#(redis.lrange(InflightQueue,0,-1)).each do |rec|
#  i += 1
#  print "#{i} ==>> #{rec}\n"
#end

i = 0
(redis.lrange(InflightQueue,0,-1)).each { |rec| i += 1 }
print "before #{i}\n"

7.times do
json_msg = redis.lpop(InflightQueue)  #[1]
puts json_msg
redis.rpush Queue, json_msg
end

i = 0
(redis.lrange(InflightQueue,0,-1)).each { |rec| i += 1 }
print "after #{i}\n"

#while ( json_msg = redis.lpop(InflightQueue, 0)[1])
#  redis.rpush Queue, json_msg
#end

