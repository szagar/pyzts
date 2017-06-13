require 's_n'
require 'redis'
require 'zts_constants'
require 'date_time_helper'

class EntryBase
  include ZtsConstants
  attr_reader :name
  def initialize(name, options={})
    @send_entry = options.fetch(:send_entry) {
      ->(entry_name,setup) {
        lstdout "send_entry(#{setup.to_human})"
        #logger.info "send_entry(#{setup.to_human})"
        routing_key = ZtsApp::Config::ROUTE_KEY[:signal][:entry] + ".#{setup.setup_src}" + ".#{entry_name}"
        #logger.debug "<-#{@core_exchange.name}/#{routing_key}) #{setup.attributes}"
        @core_exchange.publish(setup.attributes.to_json, :routing_key => routing_key, :persistent => true)
      }
    }
        
    @setup_src_list = {}
    @name = name
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
  end
  
  def config(amqp_channel)
    #logger.debug "EntryBase#config"
    @amqp_channel = amqp_channel
    @mkt_exchange = amqp_channel.topic(ZtsApp::Config::EXCHANGE[:market][:name],
                                        ZtsApp::Config::EXCHANGE[:market][:options])
    @core_exchange = amqp_channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], 
                                   ZtsApp::Config::EXCHANGE[:core][:options])
                                        
    subscriptions(amqp_channel)
  end
  
  def persist_entry(entry)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    @redis.hmset "entry:#{entry.entry_id}", entry.attributes.flatten
    secs = DateTimeHelper::secs_until_next_close
    puts "secs until entry:#{entry.entry_id} expire = #{secs}"
    @redis.expire "entry:#{entry.entry_id}", DateTimeHelper::secs_until_next_close
    status = case entry.entry_status
      when 'pending'
        EntryPending
      when'open'
        EntryOpen
      when 'triggered'
        EntryTriggered
      end  
    @redis.zadd "setup:entries:#{entry.setup_id}", status, entry.entry_id
  end
  
  def update_setup_trigger_count(entry, amount=1)
    @redis ||= Redis.new( host: ZtsApp::Config::REDIS_HOST[:name] )
    @redis.HINCRBY "setup:#{entry.setup_id}", "triggered_entries", amount
  end
  
  def subscriptions
    #logger.debug "EntryBase#subscriptions"
  end
  
  def qualify?(setup)
    @setup_src_list.member?(setup.setup_src)
  end
  
  def add_setup_src(setup_src)
    lstdout "EntryBase#add_setup_src(#{setup_src})"
    #logger.info "EntryBase#add_setup_src(#{setup_src})"
    @setup_src_list[setup_src] = true
  end
  
  def add_entry(attributes)
    lstdout "#{__FILE__}(#__LINE__})add_entry(#{attributes})"
    #logger.debug "EntryBase#add_entry(#{setup})"

    entry              = EntryStruct.from_hash(attributes)
    entry.entry_id     = SN.next_entry_id.to_s
    entry.entry_status = 'pending'
    
    lstdout "entry=#{entry}"

    case entry.side
    when 'long'
      entry.action = 'buy'
    when 'short'
      entry.action = 'sell'
    else
      lstderr "EntryBase#add_entry side(#{entry.size}) NOT known"
      raise "EntryBase#add_entry side(#{entry.size}) NOT known"
    end

    lstdout "entry: #{entry}"
    persist_entry(entry)
    entry
  end
  
#  def setups
#    @setups
#  end
  
  def req_md(mkt, sec_id)
    msg = {:sec_id => sec_id, :mkt => mkt, :action => "on"}
    routing_key = ZtsApp::Config::ROUTE_KEY[:request][:bar5s]
    #logger.debug "<-#{@mkt_exchange.name}/#{routing_key}(#{msg}"
    @mkt_exchange.publish(msg.to_json, :routing_key => routing_key)  
  end
  
end
