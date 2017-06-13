$: << "#{ENV['ZTS_HOME']}/lib"
#require "redis_store"
require "store_mixin"
require "log_helper"
require "entry_strategy_reversal_v1"
require "entry_strategy_bir_v1"
require "entry_strategy_prebuys_position"
require "entry_strategy_prebuys_swing"
require "entry_strategy_naught"
require "string_helper"
#class String
#  def camelize
#    self.split("_").each {|s| s.capitalize! }.join("")
#  end
#end

class SystematicStore # < RedisStore
  include LogHelper
  include Store

  def initialize
    show_info "SystematicStore#initialize"
    super
  end

  def whoami
    self.class.to_s
  end

  def strategies(param)
puts "SystematicStore#strategies(#{param})"
    raw = redis.keys "systematic:*#{param}*"
    show_info "SystematicStore#strategies: raw=#{raw}"
    filter = (raw.map { |r| r[/systematic:(.*)/,1] }).map { |s| s.gsub(":","_") }
    filter.map do |sn|
      show_info "setting up strategy #{sn}"
      strategy_class = self.class.const_get("EntryStrategy#{sn.camelize}")
      strategy_class.new
    end
  rescue
    EntryStrategyNaught.new
    alert "Entry strategy: EntryStrategy not found! : EntryStrategy#{sn.camelize}"
  end

  #######
  private
  #######

  #def redis
  #  @redis ||= RedisFactory.instance.client
  #end

end
