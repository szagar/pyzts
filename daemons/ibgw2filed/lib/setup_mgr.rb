#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'setup_struct'
require 'zts_constants'
require 'my_config'
require 'amqp_factory2'
require "last_value_cache"
require "s_m"
require "log_helper"
require "setup_queue/producer"

require 'stringio'
require 'json'
require 'pp'

Queues = { development: "queue:setups:dev_account",
           test:        "queue:setups:paper",
           production:  "queue:setups:broker"
         }

class InvalidSetupError  < StandardError; end

class SetupMgr
  include LogHelper
  include ZtsConstants

  attr_reader :lvc, :sec_master, :env

  def initialize
    @env = ENV['ZTS_ENV']
    Zts.configure { |config| config.setup }
    @lvc        = LastValueCache.instance
    @sec_master = SM.instance

    @setup_queue = establish_setup_queue(@env)
  end

  def config_env(env=ENV['ZTS_ENV'])
    puts "config_env(#{env})"
    Zts.configure(env) { |config| config.setup }
  end

  def config_setup(data={})
    data = setup_defaults(data)

    setup = SetupStruct.new
    setup.status            = data[:status]             || "valid"
    setup.sec_id            = data[:sec_id]
    setup.pos_id            = data[:pos_id]             || nil
    setup.ticker            = data[:ticker]
    setup.trade_type        = data[:trade_type]         || nil
    setup.mkt               = data[:mkt]                || "stock"
    setup.side              = data[:side]               || "long"
    setup.setup_src         = data[:setup_src]          || "setup_test1"
    setup.trailing_stop_type= data[:trailing_stop_type] || "atr"
    setup.notes             = data[:notes]              || ""
    setup.tags              = data[:tags ]              || ""
    setup.pyramid_pos       = data[:pyramid_pos ]       || "false"
    setup.entry_signal      = data[:entry_signal]
    setup.entry_filter      = data[:entry_filter]
    setup.mca_tkr           = data[:mca_tkr]
    setup.mca               = data[:mca]
    setup.entry_stop_price  = data.fetch(:entry_stop_price) {nil}
    setup.limit_price       = data.fetch(:limit_price) {nil}
    (setup.atr              = data[:atr])               if (data[:atr].is_a? Numeric)
    (setup.support          = data[:support])           if (data[:support].is_a? Numeric)
    (setup.weak_support     = data[:weak_support])      if (data[:weak_support].is_a? Numeric)
    (setup.moderate_support = data[:moderate_support])  if (data[:moderate_support].is_a? Numeric)
    (setup.strong_support   = data[:strong_support])    if (data[:strong_support].is_a? Numeric)
    (setup.avg_run_pt_gain  = data[:avg_run_pt_gain])   if (data[:avg_run_pt_gain].is_a? Numeric)
    (setup.tgt_gain_pts     = data[:tgt_gain_pts])      if (data[:tgt_gain_pts].is_a? Numeric)
    setup
  rescue =>e
    warn "config_setup failed for: #{data}"
    warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    NullSetup.new
  end

  def set_limit_price(side,stop_price,limit_price=null)
    limit_price.is_a?(Numeric) ? limit_price : calc_limit_price_from_stop(side,stop_price)
  end

  def set_entry_stop(side,entry_stop=null)
    puts "set_entry_stop(#{side},#{entry_stop})"
    #calc_entry_stop_price(side) unless entry_stop.is_a?(Numeric)
    entry_stop.is_a?(Numeric) ? entry_stop : calc_entry_stop_price(side)
  end

  def set_trailing_stop_type(support=null)
    debug "set_trailing_stop_type: support =  #{support}/#{support.class}"
    debug "set_trailing_stop_type was #{set_trailing_stop_type}"
    (MiscHelper::is_a_number?(:support)) ? "support" : "atr"
  end

  def calc_entry_stop_price(side,work_price=null)
    work_price = (side == "short") ? get_price('low') : get_price('high')
    px_adj =  (work_price < 10) ? 0.12 : 0.25
    px_adj =  0.06 if work_price < 5.0
    (side == "short") ? work_price-px_adj : work_price+px_adj
  end

  def get_price(field)
    puts "get_price(#{field})"
    99.99
  end

  def setup_defaults(data={})
    data[:sec_id] ||= sec_master.sec_lookup(data[:ticker])
    data[:ticker] ||= sec_master.stock_tkr(data[:sec_id])
    sec_id          = data[:sec_id]
    data[:status]   = "valid"
    data[:side]   ||= "long"
    data[:trailing_stop_type] ||= set_trailing_stop_type(data[:support])
    data[:entry_signal]     ||= "pre-buy"
    data[:entry_stop_price]   = set_entry_stop(data[:side],data[:entry_stop_price])
    data[:limit_price]        = set_limit_price(data[:side],data[:entry_stop_price],
                                                data[:limit_price])

    case data[:entry_signal]
    when "systematic"
      data[:trade_type]        ||= "Position"
    when "dragon"
      data[:trade_type]        ||= "Position"
      data[:side]              ||= "long"
    when "ema"
      data[:entry_signal]        = "pre-buy"
      data[:trailing_stop_type]  = "ema"
      data[:trade_type]        ||= "Position"
      data[:side]              ||= "long"
      level = (data[:side] == "long") ? "high" : "low"
      data[:entry_stop_price]    = lvc.ema(sec_id,level,34)
      check_stop_price_alignment(data)
    when "pre-buy"
      data[:entry_signal]         = "pre-buy"
      data[:trailing_stop_type] ||= "support"
      data[:trade_type]         ||= "Position"
      data[:side]               ||= "long"
      check_entry_stop(data)
    when "springboard"
      data[:entry_signal]         = "springboard"
      data[:trailing_stop_type] ||= "support"
      data[:trade_type]        ||= "Position"
      data[:side]               ||= "long"
      check_pts(data)
      check_support(data)
    end

    data
  end
 
  def send_setup(exchange,setup)
    #return unless setup.valid?
    routing_key = Zts.conf.rt_setups
    transcript = StringIO.new
    if setup.valid?(transcript)
      puts "<-(#{exchange.name}/#{routing_key}) "\
               "#{setup[:setup_src]} #{setup[:ticker]} #{setup[:side]} entry stop: #{setup[:entry_stop_price]} ="\
               "#{setup[:trailing_stop_type]}= "\
               "support:#{setup.attributes.fetch('support'){'NA'}} "\
               "trade_type:#{setup[:trade_type]} "
      exchange.publish(setup.attributes.to_json, :routing_key => routing_key)
    else
      warn transcript.string
    end
  end

  #def submit(setup)
  def queue_setup(setup)
    transcript = StringIO.new
    if setup.valid?(transcript)
      @setup_queue.push(SetupQueue::Message.new(command: "new_setup", data:    setup.attributes ))
    else
      warn transcript.string
    end
  end

  def run(setups)
    EventMachine.run do
      connection,channel = AmqpFactory.instance.channel
      exchange           = channel.topic(Zts.conf.amqp_exch_flow,
                                         Zts.conf.amqp_exch_options)
      puts "Creating setups..."
      routing_key = Zts.conf.rt_setups
      setups.flatten.each do |setup|
        next unless setup.valid?
        transcript = StringIO.new
        #if valid_setup?(setup,transcript)
        if setup.valid?(transcript)
          puts "<-(#{exchange.name}/#{routing_key}) "\
               "#{setup[:setup_src]} #{setup[:ticker]} buy stop: #{setup[:entry_stop_price]} ="\
               "#{setup[:trailing_stop_type]}= "\
               "support:#{setup.attributes.fetch('support'){'NA'}} "\
               "trade_type:#{setup[:trade_type]} "
          exchange.publish(setup.attributes.to_json, :routing_key => routing_key)
        else
          warn transcript.string
        end
      end

      show_stopper = Proc.new {
        connection.close { EventMachine.stop }
      }
      EM.add_timer(2, show_stopper)
    end
  end

  ###############
  private
  ###############

  def production?;  env == "production";  end
  def test?;        env == "test";        end
  def development?; puts "-->env=#{env}"; env == "development"; end

  def valid_price?(price)
    (price.is_a?(Numeric) && price > 0.0)
  end

  def valid_id?(id)
    (id.is_a?(Integer) && id > 0)
  end

  def check_stop_price_alignment(data)
    side_factor = (data[:side] == "long") ? 1 : -1
    last_price = lvc.last(data[:sec_id])
    unless (data[:entry_stop_price] - last_price) * side_factor > 0
      warn "stop price misaligned with last price"  
      raise InvalidSetupError.new, "stop price(#{data[:entry_stop_price]}) " \
            "mis-aligned with last price(#{last_price})"
    end
  end

  def check_entry_stop(data)
    puts "check_entry_stop(data): data = #{data}"
    puts "check_entry_stop(data): data[:entry_stop_price] = #{data[:entry_stop_price]}"
    unless valid_price?(data[:entry_stop_price].to_f)
      warn "#{data[:ticker]}: pre-buy requires valid entry stop price" \
           "(#{data[:entry_stop_price]})"
      raise InvalidSetupError.new, "#{data[:ticker]}: pre-buy requires " \
            "valid entry stop price(#{data[:entry_stop_price]})"
    end
  end

  def check_pts(data)
    unless data[:avg_run_pt_gain] ||
           data[:tgt_gain_pts]
      warn "#{data[:ticker]}: #{data[:entry_signal]} " \
           "requires valid reward number (avg_run_pt_gain or tgt_gain_pts)"
      raise InvalidSetupError.new, "#{data[:ticker]}: " \
            "requires valid reward number (avg_run_pt_gain or tgt_gain_pts)"
    end
  end

  def check_support(data)
    unless valid_price?(data[:support].to_f)      ||
           valid_price?(data[:weak_support].to_f) ||
           valid_price?(data[:moderate_support].to_f)
      warn "#{data[:ticker]}: #{data[:entry_signal]} " \
           "requires valid support level (support, weak_support, or moderate_support"
      raise InvalidSetupError.new, "#{data[:ticker]}: #{data[:entry_signal]} " \
            "requires valid support level (support, weak_support, or moderate_support)"
    end
  end

  def establish_setup_queue(env)
    q = Queues[env.to_sym]
    puts "@setup_queue = SetupQueue::Producer.new(#{q})"
    @setup_queue = SetupQueue::Producer.new(q)
  end


end

