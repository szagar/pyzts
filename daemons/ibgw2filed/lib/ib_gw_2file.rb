#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"
$: << "#{ENV['ZTS_HOME']}/ib"

require 'store_mixin'
require 'order_struct'
require "s_m"
require "e_wrapper_2file"
require "ib-ruby"
require "json"
require "my_config"
require 'configuration'
require 'mkt_subscriptions'
require "log_helper"

module EchoServer
  def initialize(gw,ew)
    @gw = gw
    @ew = ew
    puts "EchoServer#initialize: @gw=#{@gw}"
    puts "EchoServer#initialize: @ew=#{@ew}"
  end

  def post_init
    puts "-- someone connected to the echo server!"
  end

  def list_commands
      puts <<PUTS
          ls            : list commands
          log           : set log level: 0: warn, 2: info, 3:debug
          q             : exit daemon
          poo           : print open orders
          goo           : get open orders
          init tkr      : setup lvc and start monitoring
          pr risk_per   : change percent risk per position
          prisk         : show $ risk amount for next trade
          size          : size matrix for each tkr
          atrsl         : trade size for ATR factors
          lvc           : show last value cache
          acct          : show account values
          portf         : show portfolio positions
          orders        : TBD

          Order Types   :
          s tkr <pos risk $>       : sell tkr @ max(bid,mid)
          b tkr <pos risk $>       : buy tkr @ min(ask,mid)
          bl tkr lmt_price         : buy tkr @ lmt_price
          sl tkr lmt_price         : sell tkr @ lmt_price
          bs tkr stop_px stop_loss : buy stop order
          ss tkr stop_px stop_loss : sell stop order
          r2g tkr                  : buy when price goes from red to green
          g2r tkr                  : sell when price goes from green to red
          bs30atr tkr stop_px      : buy stop order, set stop loss @ 30% of ATR
                                   :     sell half size @ stop + 1R
          ss30atr tkr stop_px      : sell stop order, set stop loss @ 30% of ATR
                                   :     sell half size @ stop - 1R
PUTS
  end

  def receive_data data
    puts "GOT IT ******************************** #{data}\n"
    args = []
    begin
      args = data.chomp.split(' ')
      command = args.shift
    rescue
      warn "WARNING: problems with data: #{data}"
    end
    return unless command
    puts "command=#{command}"
    puts "args=#{args}"

    nop = true

    case command.downcase
    when "ls"
      list_commands
    when "log"
      @gw.set_log_level(args[0].to_i)
    when "goo"
      @gw.request_open_orders
    when "poo"
      @gw.print_open_orders2
    when "pr"
      @gw.set_position_risk_percent(args[0].to_f)
    when "init"
      args.each { |tkr| @gw.subscribe_ticks(tkr) }
    when "prisk"
      puts "Position risk for next trade ... #{@gw.position_risk_dollars.round(2)}"
    when "size"
      @gw.print_size_options
    when "atrsl"
      @gw.print_atr_stop_loss
    when "lvc"
      @gw.print_lvc
    when "orders"
      @gw.print_orders
    when "acct"
      @gw.print_account
    when "portf"
      @gw.print_portf
    when "s"         # sell : s IBM 50 => buy at offer, risk 50
      @gw.s_order(tkr: args[0], pos_risk: @gw.position_risk_dollars)
    when "b"         # buy : bs IBM 50 => buy at offer, risk 50
      @gw.b_order(tkr: args[0], pos_risk: @gw.position_risk_dollars)
    when "bl"         # buy : bl IBM 105.25 => buy limit price
      @gw.lmt_b_order(tkr: args[0], lmt_px: args[1], stop_loss: args[2]||false, pos_risk: @gw.position_risk_dollars)
    when "sl"         # buy : bl IBM 105.25 => buy limit price
      @gw.lmt_s_order(tkr: args[0], lmt_px: args[1], pos_risk: @gw.position_risk_dollars)
    when "bs"         # buy stop: bs IBM 105.25 101.25 50 => stop entry@105.25 stop loss@101.25 risk 50
      @gw.bs_order(tkr: args[0], stop_px: args[1], stop_ex: args[2], pos_risk: @gw.position_risk_dollars, half_at_2R: false)
    when "ss"         # sell stop
      @gw.ss_order(tkr: args[0], stop_px: args[1], stop_ex: args[2], pos_risk: @gw.position_risk_dollars)
    when "r2g"         # red to green
      @gw.r2g_order(tkr: args[0], pos_risk: args[1]||@gw.position_risk_dollars)
    when "g2r"         # green to red
      @gw.g2r_order(tkr: args[0], pos_risk: args[1]||@gw.position_risk_dollars)
    when "bs30atr"     # bs order with 30% of ATR as init stop loss
      @gw.bs_atr_stop_atr_target_order(tkr: args[0], stop_px: args[1],
                                       stop_factor: 0.30,
                                       tgt_factor: 1.0,
                                       pos_risk: args[2]||@gw.position_risk_dollars)
    when "ss30atr"     # ss order with 30% of ATR as init stop loss
      @gw.ss_atr_stop_atr_target_order(tkr: args[0], stop_px: args[1],
                                       stop_factor: 0.30,
                                       tgt_factor: 1.0,
                                       pos_risk: args[2]||@gw.position_risk_dollars)
    when "exit","quit","q"
      exit 0
    else
      warn "command: #{command} not recognized"
    end
    send_data ">>> you sent: #{data}  command: #{command}  args: #{args}\n"
  end
end

class IbGw
  include LogHelper
  include Store

  attr_reader :thread_id
  attr_reader :sid_map, :tkr_map
  attr_reader :ib, :mkt_data_server
  attr_reader :lvc, :account, :portf, :working_orders, :orders, :order_lookup
  attr_reader :parent_orders, :child_orders, :all_orders

  def initialize(broker,opts={})
    show_info "IbGw#initialize"
    DaemonKit.logger.level = :info

    this_host = `hostname`.chomp[/(.*)\..*/,1]

    puts "Broker is #{broker}"
    broker_config = opts[:config] ||=
             Configuration.new({filename: "ib_#{this_host}.yml",
                                env:      broker})
  
    @parent_orders = {}
    @child_orders = {}
    @all_orders = {}

    @contracts = {}
    @sid_map = {}
    @tkr_map = {}
    @lvc     = {}
    @working_orders  = {}
    @account = {}
    @orders = {}
    @order_lookup = {}
    @portf   = {}
    @broker = broker
    @position_risk_percent = 0.50
    @atr_factor_sl_long = 0.5
    @atr_factor_sl_short = 0.5
    @mkt_subs           = MktSubscriptions.instance
    @mkt_data_server    = broker_config.md_status == "true" ? true : false
    @mkt_data_server_id = broker_config.md_id
    puts "Ticker Plant #{@mkt_data_server_id} is #{@mkt_data_server ? 'on' : 'off'}"
 
    today = DateTimeHelper::integer_date
    ib_data_dir = "/Users/szagar/zts/data/ibdata"
    (@fh_warn   = File.open("#{ib_data_dir}/#{today}_warnings.csv", 'w')).sync = true
    (@fh_submissions = File.open("#{ib_data_dir}/#{today}_submissions.csv", 'w')).sync = true

    submission_file_hdr

    ib_app = opts[:ib_app] ||= "gw"
    port   = broker_config.send("#{ib_app}_port")
    puts "@ib = IB::Connection.new :host      => #{broker_config.host}, \
                                   :client_id => #{broker_config.client_id}, \
                                   :port      => #{port}"
    @ib = IB::Connection.new(:host      => broker_config.host,
                             :client_id => broker_config.client_id,
                             :port      => port)


    puts "@ib=#{@ib}"
    @ib.wait_for :NextValidId
 
    @progname    = File.basename(__FILE__,".rb")
    @local_subs  = {}

    @sec_master = SM.instance

    puts "IB Gateway, program name : #{@progname}"
    puts "            tkr plant    : #{@mkt_data_server_id} is #{mkt_data_server ? 'on' : 'off'}"

    start_ewrapper

    @thread_id = Thread.new {
      EventMachine::run {
        EventMachine::start_server "127.0.0.1", 8081, EchoServer, self, @ew
        puts 'running echo server on 8081'
      }
    }

    @debug_level = 3
    @info_level  = 2
    @warn_level  = 0
    set_log_level(@debug_level)

    #show_info "Start EM thread"
    #@thread_id = Thread.new { EventMachine.run }
    if defined?(JRUBY_VERSION)
     # on the JVM, event loop startup takes longer and .next_tick behavior
     # seem to be a bit different. Blocking current thread for a moment helps.
     sleep 0.5
    end

  end

  def active_mkt_data_server?
    @mkt_data_server
  end
  
  def set_position_risk_percent(r)
    @position_risk_percent = r
    show_info "position risk set to #{@position_risk_percent}"
  end

  def submission_file_hdr
    @fh_submissions.write 'ib_order_id,'
    @fh_submissions.write 'tkr,'
    @fh_submissions.write 'quantity,'
    @fh_submissions.write 'limit_price,'
    @fh_submissions.write 'aux_price,'
    @fh_submissions.write 'side,'
    @fh_submissions.write 'order_type,'
    @fh_submissions.write 'parent_id,'
    @fh_submissions.write 'transmit,'
    @fh_submissions.write 'created_at,'
    @fh_submissions.write 'updated_at,'
    @fh_submissions.write 'discretionary_amount,'
    @fh_submissions.write 'tif,'
    @fh_submissions.write 'open_close,'
    @fh_submissions.write 'origin,'
    @fh_submissions.write 'short_sale_slot,'
    @fh_submissions.write 'trigger_method,'
    @fh_submissions.write 'oca_type,'
    @fh_submissions.write 'auction_strategy,'
    @fh_submissions.write 'designated_location,'
    @fh_submissions.write 'exempt_code,'
    @fh_submissions.write 'display_size,'
    @fh_submissions.write 'continuous_update,'
    @fh_submissions.write 'delta_neutral_con_id,'
    @fh_submissions.write 'algo_strategy,'
    @fh_submissions.write 'what_if,'
    @fh_submissions.write 'leg_prices,'
    @fh_submissions.write 'algo_params,'
    @fh_submissions.write "combo_params\n"
  end

  def active_ticker?(tkr)
    if not @lvc.has_key?(@tkr_map[tkr])
      warn "Ticker #{tkr} not active"
      return false
    end
    return true
  end

  def invalid_limit2stop_loss?(side,limit_price,stop_loss)
    if side == 'long'
      return false if (limit_price-stop_loss) > 0.05 
    end
    if side == 'short'
      return false if (stop_loss-limit_price) > 0.05 
    end
    warn "No trade, limit-to-stop relationship for #{side} is invalid.  limit_price=#{limit_price}, stop_loss=#{stop_loss}"
    @fh_warn.write "No trade, limit-to-stop relationship for #{side} is invalid.  limit_price=#{limit_price}, stop_loss=#{stop_loss}\n"
    return true
  end

  def invalid_size?(size)
    if size < 5
      warn "size(#{size}) invalid, under 5."
      warn "No trade, size#{size} under 5."
      @fh_warn.write "No trade, size#{size} under 5.\n"
      return true
    end
    return false
  end

  def invalid_limit_price?(limit_price)
    unless limit_price
      warn "No trade, invalid limit_price: #{limit_price}"
      @fh_warn.write "No trade, invalid limit_price: #{limit_price}\n"
      return true
    end
    unless limit_price > 0.05
      warn "No trade, invalid limit_price: #{limit_price}"
      @fh_warn.write "No trade, invalid limit_price: #{limit_price}\n"
      return true
    end
    return false
  end
  def g2r_order(o)
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    last_price = @lvc[sid][:last_price]
    prev_close = @lvc[sid][:prev_close]
    if last_price < prev_close
      @fh_warn.write "g2r_order: #{tkr} Price already red, no order staged"
      return
    end
    stop_loss = prev_close + @lvc[sid][:atr14]*@atr_factor_sl_short
    ss_order(tkr: tkr, stop_px: prev_close, stop_ex: stop_loss, pos_risk: o[:pos_risk])
  end

  def r2g_order(o)
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    last_price = @lvc[sid][:last_price]
    prev_close = @lvc[sid][:prev_close]
    if last_price > prev_close
      @fh_warn.write "Price already green, no order staged\n"
      return
    end
    stop_loss = prev_close - @lvc[sid][:atr14]*@atr_factor_sl_long
    #debug "r2g_order: bs_order(tkr: #{tkr}, stop_px: #{prev_close}, stop_ex: #{stop_loss}, pos_risk: #{o[:pos_risk]}, half_at_2R: false)"
    bs_order(tkr: tkr, stop_px: prev_close, stop_ex: stop_loss, pos_risk: o[:pos_risk], half_at_2R: false)
  end

  #  (tkr:, stop_px:, stop_factor:, tgt_factor:, pos_risk:)
  def bs_atr_stop_atr_target_order(o)
    debug "bs_atr_stop_atr_target_order(#{o})"
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    atr = @lvc[sid][:atr14]
    stop_px = o[:stop_px].to_f
    stop_ex = stop_px - o[:stop_factor].to_f * atr
    tgt_price = stop_px + o[:tgt_factor].to_f * atr
    #debug "bs_atr_stop_atr_target_order: bs_order(tkr: #{tkr}, stop_px: #{stop_px}, stop_ex: #{stop_ex}, tgt_price: #{tgt_price}, pos_risk: #{o[:pos_risk]}, half_at_2R: true)"
    bs_order(tkr: tkr, stop_px: stop_px, stop_ex: stop_ex, tgt_price: tgt_price,
             half_at_2R: true, pos_risk: o[:pos_risk], half_at_2R: true)
  end

  #  (tkr:, stop_px:, stop_factor:, tgt_factor:, pos_risk:)
  def ss_atr_stop_atr_target_order(o)
    debug "ss_atr_stop_atr_target_order(#{o})"
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    atr = @lvc[sid][:atr14]
    stop_px = o[:stop_px].to_f
    stop_ex = stop_px + o[:stop_factor].to_f * atr
    #debug "ss_atr_stop_atr_target_order: ss_order(tkr: #{tkr}, stop_px: #{stop_px}, stop_ex: #{stop_ex}, pos_risk: #{o[:pos_risk]})"
    ss_order(tkr: tkr, stop_px: stop_px, stop_ex: stop_ex, pos_risk: o[:pos_risk])
  end

  def buy_limit(tkr,size,limit_price)
    setup = "descretionary"
    show_info "buy_limit: #{size} #{tkr} @ #{limit_price}"
    buy_order = IB::Order.new :total_quantity => size,
                              :limit_price => limit_price,
                              :action => 'BUY',
                              :tif    => 'GTC',
                              :order_type => 'LMT',
                              :algo_strategy => '',
                              #:account => account_code,
                              :transmit => true
    #ib.wait_for :NextValidId
    place_order buy_order, @contracts[tkr]
    working_orders[tkr][:entry_order] = {:id        => buy_order.local_id,
                                 :descr     => setup,
                                 :status    => "staged",
                                 :order_qty => size,
                                 :filled    => 0}
    ib.wait_for :NextValidId
    return buy_order.local_id
  end

  def sell_limit(tkr,size,limit_price)
    setup = "descretionary"
    debug "sell_limit: #{size} #{tkr} @ #{limit_price}"
    sell_order = IB::Order.new :total_quantity => size,
                              :limit_price => limit_price,
                              :action => 'SELL',
                              :tif    => 'GTC',
                              :order_type => 'LMT',
                              :algo_strategy => '',
                              #:account => account_code,
                              :transmit => true
    #ib.wait_for :NextValidId
    place_order sell_order, @contracts[tkr]
    working_orders[tkr][:entry_order] = {:id        => sell_order.local_id,
                                 :descr     => setup,
                                 :status    => "staged",
                                 :order_qty => size,
                                 :filled    => 0}
    ib.wait_for :NextValidId
    return sell_order.local_id
  end

  def long_stop_loss(tkr,size,stop_loss_price,parent_id)
    show_info "long_stop_loss: #{size} #{tkr} stop_loss @ #{stop_loss_price}"
    stop_order = IB::Order.new :total_quantity => size,
                               :limit_price => 0,
                               :aux_price => stop_loss_price,
                               :action => 'SELL',
                               :tif    => 'GTC',
                               :order_type => 'STP',
                               #:account => account_code,
                               :parent_id => parent_id,
                               :transmit => true
    place_order stop_order, @contracts[tkr]
  end

  def short_stop_loss(tkr,size,stop_loss_price,parent_id)
    show_info "short_stop_loss: #{size} #{tkr} stop_loss @ #{stop_loss_price}"
    stop_order = IB::Order.new :total_quantity => size,
                               :limit_price => 0,
                               :aux_price => stop_loss_price,
                               :action => 'BUY',
                               :tif    => 'GTC',
                               :order_type => 'STP',
                               #:account => account_code,
                               :parent_id => parent_id,
                               :transmit => true
    place_order stop_order, @contracts[tkr]
  end


  def long_profit_taker(tkr,size,profit_price,parent_id)
    show_info "long_profit_taker: #{size} #{tkr} profit_price @ #{profit_price}"
    profit_order = IB::Order.new :total_quantity => size,
                                 :limit_price => profit_price,
                                 :action => 'SELL',
                                 :tif    => 'GTC',
                                 :order_type => 'LMT',
                                 :parent_id => parent_id,
                                 :transmit => true
    place_order profit_order, @contracts[tkr]
  end

  def short_profit_taker(tkr,size,profit_price,parent_id)
    show_info "short_profit_taker: #{size} #{tkr} profit_price @ #{profit_price}"
    profit_order = IB::Order.new :total_quantity => size,
                                 :limit_price => profit_price,
                                 :action => 'BUY',
                                 :tif    => 'GTC',
                                 :order_type => 'LMT',
                                 :parent_id => parent_id,
                                 :transmit => true
    place_order profit_order, @contracts[tkr]
  end


  def lmt_b_order(o)
    debug "lmt_b_order(#{o})"
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    working_orders[tkr] ||= {}
    limit_price = o[:lmt_px].to_f
    return if invalid_limit_price?(limit_price)

    atr = @lvc[sid][:atr14]
    stop_loss = o[:stop_loss].to_f || (limit_price - atr * 0.5).round(2)
    return if invalid_limit2stop_loss?('long',limit_price,stop_loss)

    profit_price = (limit_price + atr * 2)
    size = (o[:pos_risk].to_f / (limit_price-stop_loss)).round(0)
    return if invalid_size?(size)
    entry_order_id = buy_limit(tkr,size,limit_price)
    long_stop_loss(tkr,size,stop_loss,entry_order_id)
    long_profit_taker(tkr,size,profit_price,entry_order_id) if (profit_price - limit_price) > (limit_price - stop_loss)
  end

  def lmt_s_order(o)
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    working_orders[tkr] ||= {}
    limit_price = o[:lmt_px].to_f

    atr = @lvc[sid][:atr14]
    stop_loss = (limit_price + atr * 0.5).round(2)
    profit_price = (limit_price - atr * 2)
    return if invalid_limit2stop_loss?('short',limit_price,stop_loss)
    size = (o[:pos_risk].to_f / (stop_loss-limit_price)).round(0)
    return if invalid_size?(size)
    entry_order_id = sell_limit(tkr,size,limit_price)
    short_stop_loss(tkr,size,stop_loss,entry_order_id)
    short_profit_taker(tkr,size,profit_price,entry_order_id)
  end



  def b_order(o)
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    setup = "descretionary"
    sid = @tkr_map[tkr]
    working_orders[tkr] ||= {}
    ask_price = @lvc[sid][:ask_price]
    mid_price = (ask_price + @lvc[sid][:bid_price])/2
    limit_price = [ask_price,mid_price].min.round(2)
    debug "b_order: #{@lvc[sid]}"
    atr = @lvc[sid][:atr14]
    debug "b_order: atr=#{atr}"
    stop_loss = (limit_price - atr * 0.5)
    profit_price = (limit_price + atr * 2)
    debug "\nb_order: limit_price=#{limit_price}/#{limit_price.class}"
    #debug "b_order: stop_loss=#{stop_loss}/#{stop_loss.class}"
    debug "here"
    debug "stop_loss = #{stop_loss}"
    stop_loss = stop_loss.round(2)
    debug "stop_loss = #{stop_loss}"
    if (limit_price-stop_loss) < 0.05 
      return 
    end
    debug "now here"
    debug o[:pos_risk].to_f
    debug limit_price-stop_loss
    size = (o[:pos_risk].to_f / (limit_price-stop_loss)).round(0)
    return if invalid_size?(size)
    debug "buy #{tkr} @#{limit_price}"
    entry_order_id = buy_limit(tkr,size,limit_price)
    #-- Parent Order --
    stop_loss_id = long_stop_loss(tkr,size,stop_loss)
     #-- Child STOP --
    debug "send stop order"
    stop_order = IB::Order.new :total_quantity => size,
                               :limit_price => 0,
                               :aux_price => stop_loss,
                               :action => 'SELL',
                               :tif    => 'GTC',
                               :order_type => 'STP',
                               #:account => account_code,
                               :parent_id => entry_order_id,
                               :transmit => true
    #ib.wait_for :NextValidId
    place_order stop_order, @contracts[tkr]
    #orders[tkr][:stoploss_order] = {:id => stop_order.local_id,
    #                                :descr => "init stop loss",
    #                                :status    => "staged"}
    
    #-- Profit Target --
    profit_order = IB::Order.new :total_quantity => size,
                                 :limit_price => profit_price,
                                 :action => 'SELL',
                                 :tif    => 'GTC',
                                 :order_type => 'LMT',
                                 :parent_id => entry_order_id,
                                 :transmit => true
    place_order profit_order, @contracts[tkr]
    #orders[tkr][:profit_order] = {:id => profit_order.local_id,
    #                              :descr => "profit target",
    #                              :status    => "staged"}
  end

  def s_order(o)
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    sid = @tkr_map[tkr]
    #orders[tkr] |= {}
    bid_price = @lvc[sid][:bid_price]
    mid_price = (@lvc[sid][:ask_price] + bid_price)/2
    limit_price = [bid_price,mid_price].max.round(2)
    debug "s_order: #{@lvc[sid]}"
    atr = @lvc[sid][:atr14]
    debug "s_order: atr=#{atr}"
    stop_loss = (limit_price + atr * 0.5)
    oneR = stop_loss-limit_price
    debug "s_order: limit_price=#{limit_price}/#{limit_price.class}"
    debug "stop_loss = #{stop_loss}"
    stop_loss = stop_loss.round(2)
    debug "stop_loss = #{stop_loss}"
    if oneR < 0.05 
      return 
    end
    size = (o[:pos_risk].to_f / oneR).round(0)
    return if invalid_size?(size)
    debug "sell #{size}  #{tkr} @#{limit_price}"
    #-- Parent Order --
    sell_entry = IB::Order.new :total_quantity => size,
                              :limit_price => limit_price,
                              :action => 'SELL',
                              :tif    => 'GTC',
                              :order_type => 'LMT',
                              :algo_strategy => '',
                              #:account => account_code,
                              :transmit => true
    #ib.wait_for :NextValidId
    place_order sell_entry, @contracts[tkr]
    
     #-- Child STOP --
    debug "send stop order"
    debug "IB::Order.new :total_quantity => #{size},"
    stop_order = IB::Order.new :total_quantity => size,
                               :limit_price => 0,
                               :aux_price => stop_loss,
                               :action => 'BUY',
                               :tif    => 'GTC',
                               :order_type => 'STP',
                               #:account => account_code,
                               :parent_id => sell_entry.local_id,
                               :transmit => true
    #ib.wait_for :NextValidId
    place_order stop_order, @contracts[tkr]
  end

  ##   (tkr:, stop_px:, stop_ex:, pos_risk:)
  def bs_order(o)
    tkr = o[:tkr]
    half_at_2R = o[:half_at_2R]
    return if not active_ticker?(tkr)
    #orders[tkr] |= {}
    size = (o[:pos_risk].to_f / (o[:stop_px].to_f-o[:stop_ex].to_f)).to_i
    return if invalid_size?(size)
    debug "stage order to buy #{size} #{o[:tkr]} @#{o[:stop_px]}, risking #{o[:pos_risk]}"
    unless o[:stop_px].to_f > 0
      warn "must input valid entry stop price!"
      return
    end
    stop_price = (o[:stop_px].to_f).round(2)
    stop_loss  = (o[:stop_ex].to_f).round(2)
    limit_price = ((stop_price > 10) ? stop_price+0.38 : stop_price+0.12).round(2)
    #limit_price = 0
    profit_price = o[:tgt_price].to_f.round(2) || (o[:pos_risk].to_f * 4 / size + stop_price).round(2)

    debug "stop_price = #{stop_price}"
    debug "stop_loss = #{stop_loss}"
    debug "limit_price = #{limit_price}"
    debug "profit_price = #{profit_price}"

    #-- Parent Order --
    #buy_limit(tkr,size,limit_price)
    debug "send parent order"
    debug "IB::Order.new :total_quantity => #{size},"
    debug "              :limit_price => #{limit_price},"
    debug "              :aux_price => #{stop_price},"
    debug "              :action => 'BUY',"
    debug "              :order_type => 'STP',"
    debug "              :algo_strategy => '',"
    debug "              #:account => account_code,"
    debug "              :transmit => true"
    buy_order = IB::Order.new :total_quantity => size,
                              :limit_price => limit_price,
                              :aux_price => stop_price,
                              :action => 'BUY',
                              :tif    => 'GTC',
                              :order_type => 'STPLMT',
                              :algo_strategy => '',
                              #:account => account_code,
                              :transmit => true
    #ib.wait_for :NextValidId
    place_order buy_order, @contracts[tkr]
    
     #-- Child STOP --
    puts "send stop order"
    debug "IB::Order.new :total_quantity => #{size},"
    debug "              :limit_price => 0,"
    debug "              :aux_price => #{stop_loss},"
    debug "              :action => 'SELL',"
    debug "              :order_type => 'STP',"
    #puts "              :account => account_code,"
    debug "              :parent_id => #{buy_order.local_id},"
    debug "              :transmit => true"
    stop_order = IB::Order.new :total_quantity => size,
                               :limit_price => 0,
                               :aux_price => stop_loss,
                               :action => 'SELL',
                               :tif    => 'GTC',
                               :order_type => 'STP',
                               #:account => account_code,
                               :parent_id => buy_order.local_id,
                               :transmit => true
    ib.wait_for :NextValidId
    place_order stop_order, @contracts[tkr]
    
    #-- BreakEven LMT
    tgt_1  = (stop_price + 2*(stop_price - stop_loss)).round(2)
    size_1 = (size/2).round(0)
    size_2 = size - size_1
    if half_at_2R && profit_price > tgt_1
      size = size_2
      debug "breakeven_order = IB::Order.new :total_quantity => #{size_1},"
      debug "                             :limit_price => #{tgt_1},"
      debug "                             :action => 'SELL',"
      debug "                             :tif    => 'GTC',"
      debug "                             :order_type => 'LMT',"
      #debug "                             :parent_id => #{buy_order.local_id},"
      debug "                             :transmit => true"
 
      breakeven_order = IB::Order.new :total_quantity => size_1,
                                   :limit_price => tgt_1,
                                   :action => 'SELL',
                                   :tif    => 'GTC',
                                   :order_type => 'LMT',
                                   #:parent_id => buy_order.local_id,
                                   :transmit => true
      place_order breakeven_order, @contracts[tkr]
    end 
    #-- Profit LMT
    #puts "profit_order = IB::Order.new :total_quantity => #{size},"
    #puts "                               :limit_price => #{profit_price},"
    #puts "                               :action => 'SELL',"
    #puts "                               :tif    => 'GTC',"
    #puts "                               :order_type => 'LMT',"
    #puts "                               :parent_id => #{buy_order.local_id},"
    #puts "                               :transmit => true"
 
    #profit_order = IB::Order.new :total_quantity => size,
    #                               :limit_price => profit_price,
    #                               :action => 'SELL',
    #                               :tif    => 'GTC',
    #                               :order_type => 'LMT',
    #                               #:account => account_code,
    #                               :parent_id => buy_order.local_id,
    #                               :transmit => true
    #place_order profit_order, @contracts[tkr]
  end

  def ss_order(o)
    tkr = o[:tkr]
    return if not active_ticker?(tkr)
    #orders[tkr] |= {}
    size = (o[:pos_risk].to_f / (o[:stop_ex].to_f-o[:stop_px].to_f)).to_i
    return if invalid_size?(size)
    debug "stage order to sell #{size} #{o[:tkr]} @#{o[:stop_px]}, risking #{o[:pos_risk]}"
    stop_price = (o[:stop_px].to_f).round(2)
    stop_loss  = (o[:stop_ex].to_f).round(2)
    limit_price = ((stop_price > 10) ? stop_price-0.38 : stop_price-0.12).round(2)
    profit_price = (stop_price - o[:pos_risk].to_f * 4 / size).round(2)

    debug "ss_order: stop_price = #{stop_price}"
    debug "ss_order: stop_loss = #{stop_loss}"
    debug "ss_order: limit_price = #{limit_price}"
    debug "ss_order: profit_price = #{profit_price}"

    #-- Parent Order --
    debug "send parent order"
    debug "IB::Order.new :total_quantity => #{size},"
    debug "              :limit_price => #{limit_price},"
    debug "              :aux_price => #{stop_price},"
    debug "              :action => 'SELL',"
    debug "              :tif    => 'GTC',"
    debug "              :order_type => 'STPLMT',"
    debug "              :algo_strategy => '',"
    debug "              #:account => account_code,"
    debug "              :transmit => true"
    entry_order = IB::Order.new :total_quantity => size,
                              :limit_price => limit_price,
                              :aux_price => stop_price,
                              :action => 'SELL',
                              :tif    => 'GTC',
                              :order_type => 'STPLMT',
                              :algo_strategy => '',
                              #:account => account_code,
                              :transmit => true
    #ib.wait_for :NextValidId
    place_order entry_order, @contracts[tkr]
    
     #-- Child STOP --
    debug "send stop order"
    debug "IB::Order.new :total_quantity => #{size},"
    debug "              :limit_price => 0,"
    debug "              :aux_price => #{stop_loss},"
    debug "              :action => 'BUY',"
    debug "              :order_type => 'STP',"
    #puts "              :account => account_code,"
    debug "              :parent_id => #{entry_order.local_id},"
    debug "              :transmit => true"
    stop_order = IB::Order.new :total_quantity => size,
                               :limit_price => 0,
                               :aux_price => stop_loss,
                               :action => 'BUY',
                               :tif    => 'GTC',
                               :order_type => 'STP',
                               #:account => account_code,
                               :parent_id => entry_order.local_id,
                               :transmit => true
    #ib.wait_for :NextValidId
    place_order stop_order, @contracts[tkr]
    
    #-- Profit LMT
    debug "send profit order"
    debug " IB::Order.new :total_quantity => #{size},"
    debug "               :limit_price => #{profit_price},"
    debug "               :action => 'BUY',"
    debug "               :tif    => 'GTC',"
    debug "               :order_type => 'LMT',"
    debug "               :parent_id => #{entry_order.local_id},"
    debug "               :transmit => true"
    profit_order = IB::Order.new :total_quantity => size,
                                 :limit_price => profit_price,
                                 :action => 'BUY',
                                 :tif    => 'GTC',
                                 :order_type => 'LMT',
                                 #:account => account_code,
                                 :parent_id => entry_order.local_id,
                                 :transmit => true
    #ib.wait_for :NextValidId
    place_order profit_order, @contracts[tkr]
  end

  #def watch_for_new_orders
  #  return
  #  order_hash = JSON.parse(payload)
  #  $stderr.puts "order_hash=#{order_hash}"
  #  order = OrderStruct.from_hash(order_hash)
  #  $stderr.puts "ib_gw: order attributes: #{order.attributes}"
  #  $stderr.puts "contract = get_contract( #{order.mkt}, #{order.sec_id} )"
  #  contract = get_contract( order.mkt, order.sec_id )
  #  action = order.action.upcase

  #  puts "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
  #                            "limit_price: #{order.limit_price || 0}," \
  #                            "action:"" #{action}," \
  #                            "order_type => #{order.price_type}," \
  #                            "order_ref: #{order.pos_id}"

  #  show_info "order = IB::Order.new total_quantity: #{order.order_qty.to_i}," \
  #                            "limit_price: #{order.limit_price || 0}," \
  #                            "action:"" #{action}," \
  #                            "order_type => #{order.price_type}," \
  #                            "order_ref: #{order.pos_id}"
  #  ib_order = IB::Order.new :total_quantity => order.order_qty.to_i,
  #                            :limit_price => order.limit_price || 0,
  #                            :action => action,
  #                            :order_type => order.price_type,
  #                            :order_ref => order.pos_id
  #  puts ib_order

  #  place_order ib_order, contract
  #end

  #def watch_for_md_unrequests
  #  debug "mktdta monitor unreq: #{payload.inspect}(#{payload.class}), routing key is #{headers.routing_key}"
  #  rec = JSON.parse(payload)
  #  debug "rec=#{rec.inspect}(#{rec.class})"
  #  sec_id = rec["sec_id"]
  #  if sec_id == "all"
  #    unreq_md(sec_id)
  #  else
  #    mkt    = rec['mkt']
  #    force = rec['force'] || false
  #    contract = get_contract( mkt, sec_id )
  #    debug "contract: #{contract.inspect}"
  #    show_info "market data unrequest: #{contract.attributes['symbol']}(#{sec_id})   mkt(#{mkt})  force(#{force})"
  #    tkr_id = get_ticker_id( mkt, sec_id ) rescue return
  #    unreq_md(tkr_id)
  #  end
  #end

  def subscribe_admin
    #msg = JSON.parse(payload, :symbolize_names => true)
    #command = msg[:command]
    #params  = msg[:params]
    #show_info "admin message: command = #{command}"
    #show_info "admin message: params  = #{params}"
    #begin
    #  self.send(command, params) if %W(query_account_data).include? command 
    #rescue => e
    #  warn "IbGw: Problem with admin msg: #{payload}"
    #  warn e.message
    #end
  end

  def atr(tkr,pd=14)
    v = `/Users/szagar/zts/scripts/tools/atr.py -t #{tkr}`.chomp
    debug "atr  v = #{v}"
    v.to_f
  end

  def prev_ohlc(tkr)
    o,h,l,c = `/Users/szagar/zts/scripts/tools/prev_ohlc.py -t #{tkr}`.chomp.split
    debug "prev_ohlc  ohlc = #{o}/#{h}/#{l}/#{c}"
    #"#{o.to_f},#{h.to_f},#{l.to_f},#{c.to_f}"
    [o.to_f,h.to_f,l.to_f,c.to_f]
  end

  def init_lvc(tkr)
    sid = @tkr_map[tkr]
    ohlc = prev_ohlc(tkr)
    @lvc[sid] ||= {:bid_price => 0, :bid_size => 0,
                   :ask_price => 0, :ask_size => 0,
                   :last_price => 0, :last_size => 0,
                   :high_price => 0, :high_size => 0,
                   :low_price => 0, :low_size => 0,
                   :close_price => 0, :close_size => 0,
                   :atr14       => atr(tkr),
                   :prev_high   => ohlc[1],
                   :prev_low    => ohlc[2],
                   :prev_close  => ohlc[3],
                   :volume => 0,
                   :last_timestamp => 0}
  end


  def set_log_level(lvl)
    puts "set_log_level(#{lvl})"
    @current_log_level = lvl
    @ew.set_log_level(lvl)
    info "Log Level for gw set to #{lvl}"
  end


  def request_open_orders()
    @parent_orders = {}
    @child_orders = {}
    @all_orders = {}
    ib.send_message :RequestAllOpenOrders
  end

  def parent_order_id(tkr)
    return @order_lookup[tkr]['parent']
  end 
  def parent_order(tkr)
    debug @orders
    debug "order_lookup=#{@order_lookup}"
    debug "symbol=#{tkr}"
    debug "order_lookup= #{@order_lookup[tkr]}"
    oid = parent_order_id(tkr)
    debug "oid=#{oid}"
    o = @orders[oid]
    return @orders[oid]
  end
  def target_order(tkr)
    debug "target_order #{tkr}"
    oid = @order_lookup[tkr]['target']
    debug "target_order oid=#{oid}"
    return @orders[oid]
  end
  def stoploss_order(tkr)
    debug "stoploss_order #{tkr}"
    oid = @order_lookup[tkr]['stoploss']
    debug "stoploss_order oid=#{oid}"
    return @orders[oid]
  end

  def print_parent_order(order)
    debug "print_parent_order #{order}"
    rtn =  sprintf"P: %-5s%-4s%-11si%10s\n",'ID','Tkr','Action'.center(11),'Quantity'
    rtn += sprintf"P: %5d%4s%5s %-6s%5d/%5d\n",order[:oid],order[:symbol],order[:action],order[:order_type].center(11),
                                       order[:filled],order[:order_qty]
    return rtn
  end
  def print_target_order(order)
    debug "target_parent_order #{order}"
    rtn = sprintf"%4s",order[:symbol]
    return rtn
  end
  def print_stoploss_order(order)
    debug "print_stoploss_order(#{order})"
    rtn =  sprintf"S: %-5s%-4s%-11s%10s\n",'ID','Tkr','Action','Quantity'
    rtn += sprintf"S: %5d%4s%5s %-6s%5d/%5d\n",order[:oid],order[:symbol],order[:action],order[:order_type],
                                        order[:filled],order[:order_qty]
    return rtn
  end

  def print_open_orders2()
    output = {}
    output[:long] = []
    output[:short] = []
    output[:new] = []
    all_orders.keys.sort.each do |tkr|
      str_t = :new
      str_t = :long if long?(tkr)
      str_t = :short if short?(tkr)
      pre_str = sprintf "%9s %5d @%6.2f : ",tkr,position(tkr),avg_price(tkr)
      all_orders[tkr]["LimitEntry"].keys.sort.each do |oid|
        order_detail = all_orders[tkr]["LimitEntry"][oid]
        str = sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f @%6.2f\n",
                       order_detail[:my_order_type],order_detail[:parent_id],
                       order_detail[:local_id],order_detail[:open_close],
                       order_detail[:status],order_detail[:symbol],
                       order_detail[:action],order_detail[:order_type],
                       order_detail[:total_quantity],order_detail[:aux_price],
                       order_detail[:limit_price]
        output[str_t] << pre_str + str
      end
      all_orders[tkr]["StopEntry"].keys.sort.each do |oid|
        order_detail = all_orders[tkr]["StopEntry"][oid]
        str = sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f @%6.2f\n",
                       order_detail[:my_order_type],order_detail[:parent_id],
                       order_detail[:local_id],order_detail[:open_close],
                       order_detail[:status],order_detail[:symbol],
                       order_detail[:action],order_detail[:order_type],
                       order_detail[:total_quantity],order_detail[:aux_price],
                       order_detail[:limit_price]
        output[str_t] << pre_str + str
      end
      all_orders[tkr]["StopLoss"].keys.sort.each do |oid|
        order_detail = all_orders[tkr]["StopLoss"][oid]
        str = sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f%6.2f\n",
                       order_detail[:my_order_type],order_detail[:parent_id],
                       order_detail[:local_id],order_detail[:open_close],
                       order_detail[:status],order_detail[:symbol],
                       order_detail[:action],order_detail[:order_type],
                       order_detail[:total_quantity],order_detail[:aux_price],
                       order_detail[:limit_price]
        output[str_t] << pre_str + str
      end
      all_orders[tkr]["ProfitTgt"].keys.sort.each do |oid|
        order_detail = all_orders[tkr]["ProfitTgt"][oid]
        str = sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f%6.2f\n",
                       order_detail[:my_order_type],order_detail[:parent_id],
                       order_detail[:local_id],order_detail[:open_close],
                       order_detail[:status],order_detail[:symbol],
                       order_detail[:action],order_detail[:order_type],
                       order_detail[:total_quantity],order_detail[:aux_price],
                       order_detail[:limit_price]
        output[str_t] << pre_str + str
      end
    end
    info "Long positions:"
    output[:long].each { |o| info o }
    info "Short positions:"
    output[:short].each { |o| info o }
    info "New positions:"
    output[:new].each { |o| info o }
  end

  def print_open_orders()
    output = {}
    output[:long] = []
    output[:short] = []
    output[:new] = []
    prev_tkr = ""
    parent_orders.keys.sort.each do |tkr|
      str_t = :new
      str_t = :long if long?(tkr)
      str_t = :short if short?(tkr)
      #output[str_t] << "#{position(tkr)} shares of #{tkr} @#{avg_price(tkr)}"
      parent_orders[tkr].each do |o|
        if tkr != prev_tkr
          str = sprintf "%9s %5d @%6.2f : ",tkr,position(tkr),avg_price(tkr)
        else 
          str = sprintf "%25s",""
        end
        order_detail = o
        str += sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f%6.2f\n",
                       order_detail[:my_order_type],order_detail[:parent_id],
                       order_detail[:local_id],order_detail[:open_close],
                       order_detail[:status],order_detail[:symbol],
                       order_detail[:action],order_detail[:order_type],
                       order_detail[:total_quantity],order_detail[:aux_price],
                       order_detail[:limit_price]
        output[str_t] << str
        prev_tkr = tkr
      end
      if child_orders[tkr]
        child_orders[tkr].keys.each do |ot|
          child_orders[tkr][ot].each do |o|
            str = sprintf "%9s %5s %6s","","",""
            order_detail = o
            debug "order_detail=#{order_detail}"
            str += sprintf "%10s%5d/%-5d%-2s%12s%5s%5s%8s%5d%6.2f%6.2f\n",
                           order_detail[:my_order_type],
                           order_detail[:parent_id],order_detail[:local_id],
                           order_detail[:open_close],order_detail[:status],
                           order_detail[:symbol],order_detail[:action],
                           order_detail[:order_type],
                           order_detail[:total_quantity],
                           order_detail[:aux_price],
                           order_detail[:limit_price]
            output[str_t] << str
          end
        end
      end
    end

    info "Long positions:"
    output[:long].each { |o| info o }
    info "Short positions:"
    output[:short].each { |o| info o }
    info "New positions:"
    output[:new].each { |o| info o }

debug "=========================================="
debug "=========================================="
debug "=========================================="
    return

    secs = @orders.values.map {|d| d[:symbol]}.uniq.sort
    debug "secs=#{secs}"
    secs.each do |symbol|
      debug "symbol=#{symbol}"
      p_o   = parent_order(symbol)
      tgt_o = target_order(symbol)
      sl_o  = stoploss_order(symbol)
      debug "sl_o=#{sl_o}"
      str = print_parent_order(p_o)
      debug "#{str}"
      if tgt_o
        debug "tgt_o ->"
        str = print_tgt_order(tgt_o)
        debug "target: #{str}"
      end
      if sl_o
        debug "sl_o ->"
        str = print_stoploss_order(sl_o)
        debug "#{str}"
      end
    #@orders.each do |oid,order|
    #  printf "%5d %5s\n",oid,order[:symbol]
    end
  end

  def subscribe_ticks(tkr)
    mkt = 'stock'
    unless (sec_id = @sec_master.tkr_lookup(mkt, tkr))
      @fh_warn.write "Ticker: #{tkr} not found, cannot subscribe to md\n."
      return
    end
    debug "@sid_map[#{sec_id}.to_i] = #{tkr}"
    @sid_map[sec_id.to_i] = tkr
    @tkr_map[tkr] = sec_id.to_i
    @contracts[tkr] ||= get_contract( mkt, sec_id )
    contract = @contracts[tkr]
    debug "subscribe_ticks: contract: #{contract.inspect}"

    tkr_id = get_ticker_id( mkt, sec_id ) rescue return
    init_lvc(tkr)
    req_ticks(tkr_id, contract)
  end

  def print_orders
    #@orders.keys.sort.each { |t| debug "#{t}  #{@orders[t]}" }
  end

  def print_lvc
    print_tick_hdr
    tkr_map.keys.sort.each { |tkr| print_tick(tkr_map[tkr]) }
    #@lvc.keys.sort.each { |tid| print_tick(tid) }
  end

  def position_risk_dollars
    debug "NetLiquidation        = #{@account["NetLiquidation"]}"
    debug "position_risk_percent = #{@position_risk_percent}"
    @account["NetLiquidation"].to_f * @position_risk_percent/100.0
  end

  def print_account
    #debug @account
    printf "Account .................. %s\n",@account["AccountCode"]
    printf "AccountType .............. %s\n",@account["AccountType"]
    printf "AvailableFunds ........... %s\n",@account["AvailableFunds"]
    printf "BuyingPower .............. %s\n",@account["BuyingPower"]
    printf "CashBalance .............. %s\n",@account["CashBalance"]
    printf "Cushion .................. %s\n",@account["Cushion"]
    printf "EquityWithLoanValue ...... %s\n",@account["EquityWithLoanValue"]
    printf "ExcessLiquidity .......... %s\n",@account["ExcessLiquidity"]
    printf "FullAvailableFunds ....... %s\n",@account["FullAvailableFunds"]
    printf "FullExcessLiquidity ...... %s\n",@account["FullExcessLiquidity"]
    printf "GrossPositionValue ....... %s\n",@account["GrossPositionValue"]
    printf "LookAheadAvailableFunds .. %s\n",@account["LookAheadAvailableFunds"]
    printf "NetLiquidation ........... %s\n",@account["NetLiquidation"]
    printf "OptionMarketValue ........ %s\n",@account["OptionMarketValue"]
    printf "ZZZ ...................... %s\n",@account["EquityWithLoanValue"]
    printf "Percent risk / position .. %s\n",@position_risk_percent
  end

  def print_size_options
    risk0 = position_risk_dollars.round(0)
    risk1 = 50
    risk2 = 100
    printf "%-6s",""
    # default risk
    printf "%9s%8s%8s","","#{risk0} risk",""
    printf "  | "
    # $50 risk
    printf "%9s%8s%8s","","$50 risk",""
    printf "  | "
    # $100 risk
    printf "%8s%9s%8s","","$100 risk",""
    printf "\n"
    printf "%-6s",""
    printf " %4s %4s %4s %4s %4s","0.3x","1.0x","1.5x","2.0x","2.7x"
    printf "  | "
    printf " %4s %4s %4s %4s %4s","0.3x","1.0x","1.5x","2.0x","2.7x"
    printf "  | "
    printf " %4s %4s %4s %4s %4s","0.3x","1.0x","1.5x","2.0x","2.7x"
    printf "\n"
    tkr_map.keys.sort.each { |tkr|
      tid = tkr_map[tkr]
    #@lvc.keys.sort.each { |tid| 
      printf "%-6s",sid_map[tid]
      printf " %4d %4d %4d %4d %4d",
            risk0/(@lvc[tid][:atr14]*0.3),
            risk0/(@lvc[tid][:atr14]*1.0),
            risk0/(@lvc[tid][:atr14]*1.5),
            risk0/(@lvc[tid][:atr14]*2.0),
            risk0/(@lvc[tid][:atr14]*2.7)
      printf "  | "
      printf " %4d %4d %4d %4d %4d",
            risk1/(@lvc[tid][:atr14]*0.3),
            risk1/(@lvc[tid][:atr14]*1.0),
            risk1/(@lvc[tid][:atr14]*1.5),
            risk1/(@lvc[tid][:atr14]*2.0),
            risk1/(@lvc[tid][:atr14]*2.7)
      printf "  | "
      printf " %4d %4d %4d %4d %4d",
            risk2/(@lvc[tid][:atr14]*0.3),
            risk2/(@lvc[tid][:atr14]*1.0),
            risk2/(@lvc[tid][:atr14]*1.5),
            risk2/(@lvc[tid][:atr14]*2.0),
            risk2/(@lvc[tid][:atr14]*2.7)
      printf "\n"
    }
  end

  def print_atr_stop_loss
    printf "%-6s",""
    printf "%-6s","Last"
    printf " %8s %8s %8s %8s %8s","0.3x","1.0x","1.5x","2.0x","2.7x"
    printf "  | "
    printf " %4s %4s %4s %4s %4s","0.3x","1.0x","1.5x","2.0x","2.7x"
    printf "\n"
    risk1 = 50
    risk2 = 100
    #@lvc.keys.sort.each { |tid|
      #px = @lvc[tid][:last_price]
      #printf "%-6s",sid_map[tid]
    tkr_map.keys.sort.each { |tkr|
      tid = tkr_map[tkr]
      px = @lvc[tid][:last_price]
      printf "%-6s",tkr
      printf "%-6.2f",px
      printf " %8.2f %8.2f %8.2f %8.2f %8.2f",
            px - (@lvc[tid][:atr14]*0.3),
            px - (@lvc[tid][:atr14]*1.0),
            px - (@lvc[tid][:atr14]*1.5),
            px - (@lvc[tid][:atr14]*2.0),
            px - (@lvc[tid][:atr14]*2.7)
      printf "  | "
      printf " %4.1f %4.1f %4.1f %4.1f %4.1f",
            (@lvc[tid][:atr14]*0.3),
            (@lvc[tid][:atr14]*1.0),
            (@lvc[tid][:atr14]*1.5),
            (@lvc[tid][:atr14]*2.0),
            (@lvc[tid][:atr14]*2.7)
      printf "\n"
    }
  end


  def print_portf
    total_value_long  = 0
    total_value_short = 0
    total_realized    = 0
    total_unrealized  = 0
    total_lockin      = 0

    printf "%6s %6s %6s %8s %6s %8s %8s %8s %8s\n","Tkr","Qty","Last","Value","AvgPx","UnReal","Real","StopLoss","LockIn"
    @portf.keys.sort.each do |tkr|
      #puts "tkr= #{tkr}"
      #puts "keys= #{@all_orders.keys}"
      #puts "@all_orders= #{@all_orders}"
      sl = nil
      #puts tkr
      #puts @all_orders[tkr]
      @all_orders.fetch(tkr,{'StopLoss' => {}}).fetch('StopLoss').keys.each {|oid|
        sl = @all_orders[tkr]['StopLoss'][oid][:aux_price]
      }
      stop_loss = sl ? (sprintf("%8.2f",sl)) : ""
      lock_in = sl ? (sl*@portf[tkr][:position]) : 0
      #puts "lock_in = #{lock_in}"
      total_lockin += lock_in
      
      printf "%6s %6.0f %6.2f %8.2f %6.2f %8.2f %8.2f %8s %8.2f\n",
             tkr,
             @portf[tkr][:position],
             @portf[tkr][:market_price],
             @portf[tkr][:market_value],
             @portf[tkr][:average_price],
             @portf[tkr][:unrealized_pnl],
             @portf[tkr][:realized_pnl],
             #@portf[tkr][:broker_account],
             stop_loss, lock_in
      total_value_long += @portf[tkr][:market_value] if @portf[tkr][:position] > 0
      total_value_short -= @portf[tkr][:market_value] if @portf[tkr][:position] < 0
      total_realized += @portf[tkr][:realized_pnl]
      total_unrealized += @portf[tkr][:unrealized_pnl]
    end
    printf "Total value long:     %10s\n", ActionView::Base.new.number_to_currency(total_value_long)
    printf "Total value short:    %10s\n", ActionView::Base.new.number_to_currency(total_value_short)
    printf "Total UnRealized PnL: %10s\n", ActionView::Base.new.number_to_currency(total_unrealized)
    printf "Total Realized PnL:   %10s\n", ActionView::Base.new.number_to_currency(total_realized)
    printf "Total LockIn:         %10s\n", ActionView::Base.new.number_to_currency(total_lockin)
    printf "Cash:                 %10s\n", ActionView::Base.new.number_to_currency(@account["CashBalance"])
  end

  def print_tick_hdr
    printf "%-6s%6s/%-3s %6s/%-3s %6s/%-3s   %6s/%-3s  %6s/%-3s  %6s/%-3s %4s  %4s %10s %8s\n",
           "tkr","bid","sz","ask","sz","last","sz","high","sz","low","sz","last","sz","ATR","ATR%","Volume", "timestmp"
  end

  def print_tick(tid)
    printf "%-6s%6.2f/%-3d %6.2f/%-3d %6.2f/%-3d   %6.2f/%-3d  %6.2f/%-3d  %6.2f/%-3d %4.1f %4.1f %1s %10s %s \n",
            sid_map[tid],
            @lvc[tid][:bid_price],@lvc[tid][:bid_size],
            @lvc[tid][:ask_price],@lvc[tid][:ask_size],
            @lvc[tid][:last_price],@lvc[tid][:last_size],
            @lvc[tid][:high_price],@lvc[tid][:high_size],
            @lvc[tid][:low_price],@lvc[tid][:low_size],
            @lvc[tid][:last_price], @lvc[tid][:last_size],
            @lvc[tid][:atr14],
            @lvc[tid][:atr14]/@lvc[tid][:last_price]*100.0,
            (@lvc[tid][:last_price]>@lvc[tid][:prev_close])?"G":"R",
            ActionView::Base.new.number_with_delimiter(@lvc[tid][:volume]),
            Time.at(@lvc[tid][:last_timestamp].to_i).strftime("%T")
  end

  def start_ewrapper
    Fiber.new {
      @ew = EWrapper.new(@ib,self,@broker)
      @ew.run
    }.resume
  end

  def cancel_order(params=nil)
    show_action "ib.send_message :CancelOrder"
    ib.send_message :CancelOrder
  end

  def query_account_data(params=nil)
    show_action "ib.send_message :RequestAccountData"
    ib.send_message :RequestAccountData
    ib.wait_for :AccountDownloadEnd, 30
  end

  def long?(tkr)
    debug "**********long?(#{tkr})"
    return false unless portf.key?(tkr)
    debug "**********portf.key?(tkr)=#{portf.key?(tkr)}"
    portf[tkr][:position] > 0
  end

  def short?(tkr)
    debug "**********short?(#{tkr})"
    return false unless portf.key?(tkr)
    debug "**********portf.key?(tkr)=#{portf.key?(tkr)}"
    portf[tkr][:position] < 0
  end

  def position(tkr)
    portf.fetch(tkr,{:position => 0}).fetch(:position,0)
  end

  def avg_price(tkr)
    portf.fetch(tkr,{:average_price => 0}).fetch(:average_price)
  end

  ###########
  private
  ###########

  def debug(str)
    if @current_log_level >= @debug_level
      puts str
    end
  end

  def warn(str)
    if @current_log_level >= @warn_level
      puts str
    end
  end

  def info(str)
    if @current_log_level >= @info_level
      puts str
    end
  end

#DBUG:2016-05-13 09:52:27.844  place_order: <Order: @attributes={"quantity"=>105, "limit_price"=>11.18, "side"=>"S", "order_type"=>"LMT", "algo_strategy"=>"", "transmit"=>true, "created_at"=>2016-05-13 09:52:27 -0400, "updated_at"=>2016-05-13 09:52:27 -0400, "aux_price"=>0.0, "discretionary_amount"=>0.0, "parent_id"=>0, "tif"=>"DAY", "open_close"=>1, "origin"=>0, "short_sale_slot"=>0, "trigger_method"=>0, "oca_type"=>0, "auction_strategy"=>0, "designated_location"=>"", "exempt_code"=>-1, "display_size"=>0, "continuous_update"=>0, "delta_neutral_con_id"=>0, "what_if"=>false, "leg_prices"=>[], "algo_params"=>{}, "combo_params"=>{}}, @order_states=[#<IB::OrderState:0x00000102124fc8 @attributes={"status"=>"New", "filled"=>0, "remaining"=>0, "price"=>0, "average_price"=>0, "created_at"=>2016-05-13 09:52:27 -0400, "updated_at"=>2016-05-13 09:52:27 -0400}>] >

#DBUG:2016-05-13 09:52:27.844  place_order: <Contract:  @attributes={"symbol"=>"FCX", "currency"=>"USD", "sec_type"=>"STK", "exchange"=>"SMART", "created_at"=>2016-05-13 09:51:56 -0400, "updated_at"=>2016-05-13 09:51:56 -0400, "con_id"=>0, "right"=>"", "include_expired"=>false}, @description=Freeport-Mcmoran Copper & Gold >

  def place_order(ib_order, contract)
    #$stderr.puts "place_order(#{ib_order}, #{contract})"
    #@fh_submissions.write "place_order: ib_order=#{ib_order}\n"
    #@fh_submissions.write "place_order: contract=#{contract}\n"
    @ib.wait_for :NextValidId
    o_attr = ib_order.attributes
    c_attr = contract.attributes
    ib_order_id = @ib.place_order ib_order, contract

    show_info "Order Placed (IB order number = #{ib_order_id})"
    #ib.send_message :RequestAllOpenOrders

    order_states = ib_order.order_states
    #@fh_submissions.write "order_states = #{order_states}\n"

    #@fh_submissions.write "contract.attributes = #{contract.attributes}\n"
    #@fh_submissions.write "o_attr = #{o_attr}\n"

    @fh_submissions.write "#{ib_order.local_id},"
    @fh_submissions.write "#{c_attr['symbol']},"
    @fh_submissions.write "#{o_attr['quantity']},"
    @fh_submissions.write "#{o_attr['limit_price']},"
    @fh_submissions.write "#{o_attr['aux_price']},"
    @fh_submissions.write "#{o_attr['side']},"
    @fh_submissions.write "#{o_attr['order_type']},"
    @fh_submissions.write "#{o_attr['parent_id']},"
    @fh_submissions.write "#{o_attr['transmit']},"
    @fh_submissions.write "#{o_attr['created_at']},"
    @fh_submissions.write "#{o_attr['updated_at']},"
    @fh_submissions.write "#{o_attr['discretionary_amount']},"
    @fh_submissions.write "#{o_attr['tif']},"
    @fh_submissions.write "#{o_attr['open_close']},"
    @fh_submissions.write "#{o_attr['origin']},"
    @fh_submissions.write "#{o_attr['short_sale_slot']},"
    @fh_submissions.write "#{o_attr['trigger_method']},"
    @fh_submissions.write "#{o_attr['oca_type']},"
    @fh_submissions.write "#{o_attr['auction_strategy']},"
    @fh_submissions.write "#{o_attr['designated_location']},"
    @fh_submissions.write "#{o_attr['exempt_code']},"
    @fh_submissions.write "#{o_attr['display_size']},"
    @fh_submissions.write "#{o_attr['continuous_update']},"
    @fh_submissions.write "#{o_attr['delta_neutral_con_id']},"
    @fh_submissions.write "#{o_attr['algo_strategy']},"
    @fh_submissions.write "#{o_attr['what_if']},"
    @fh_submissions.write "#{o_attr['leg_prices']},"
    @fh_submissions.write "#{o_attr['algo_params']},"
    @fh_submissions.write "#{o_attr['combo_params']}\n"

  end

  def get_ticker_id(mkt, sec_id)
    @sec_master.encode_ticker(mkt, sec_id)
  end

  def get_contract( mkt, sec_id )
    show_info "get_contract( #{mkt}, #{sec_id} )"
    tkr_id = get_ticker_id(mkt, sec_id)
    #if @contracts.member?(tkr_id) then
    #  return @contracts[tkr_id]
    #else
      show_info "data = @sec_master.send(#{mkt}_indics,#{sec_id})"
      data = @sec_master.send("#{mkt}_indics",sec_id)
      #debug "mkt=#{mkt}"
      sec_exchange = 'SMART'
      sec_exchange = data['exchange'] if (mkt == :index)
      #show_info "@contracts[tkr_id] = IB::Contract.new(:symbol => #{data['ib_tkr']},"
      #show_info "                                     :currency => USD,"
      ##show_info "                                     :sec_type => 'STK',"
      #show_info "                                     :sec_type => :stock,"
      #show_info "                                     :exchange => #{sec_exchange},"
      #show_info "                                     :description => #{data['desc']})"
      @contracts[tkr_id] = IB::Contract.new(:symbol => data['ib_tkr'],
                                           :currency => "USD",
                                           #:sec_type => 'STK',  #mkt,
                                           :sec_type => :stock,  #mkt,
                                           :exchange => sec_exchange,
                                           :description => data['desc'])
    #end
  end

  def req_ticks(ticker_id,contract)
    #msg = IB::OutgoingMessages::RequestMarketData.new({
    #                                                  :ticker_id => id,
    #                                                  :contract => contract
    #                                                })
    #ib.dispatch(msg)
    @ib.send_message IB::Messages::Outgoing::RequestMarketData.new(
                        :request_id => ticker_id,
                        :contract => contract)
  end

  def req_md(ticker_id, contract)
    debug "req_md(#{ticker_id}, #{contract.inspect})"
    show_info "req_md:Market Data Request: ticker_id=#{ticker_id} on #{@mkt_data_server_id}"

#    unless @mkt_subs.is_active?(ticker_id)
    @mkt_subs.activate(ticker_id,@mkt_data_server_id)
    show_action "@ib.send_message :RequestRealTimeBars, :ticker_id => #{ticker_id}, contract => #{contract}"
    @local_subs[ticker_id] = :on
    #@ib.send_message :RequestRealTimeBars, :ticker_id => ticker_id, :contract => contract, \
    #                 :data_type => "TRADES", :bar_size => "5 secs"
    @ib.send_message IB::Messages::Outgoing::RequestRealTimeBars.new(
                        :request_id => ticker_id,
                        :contract => contract,
                        :data_type => :trades,
                        :bar_size => 5, # Only 5 secs bars available?
                        :use_rth => true)
      #  data = { :id => ticker_id (int),
      #           :contract => Contract ,
      #           :bar_size => int/Symbol? Currently only 5 second bars are supported,
      #                        if any other value is used, an exception will be thrown.,
      #           :data_type => Symbol: Determines the nature of data being extracted.
      #                       :trades, :midpoint, :bid, :ask, :bid_ask,
      #                       :historical_volatility, :option_implied_volatility,
      #                       :option_volume, :option_open_interest
      #                       - converts to "TRADES," "MIDPOINT," "BID," etc...
      #          :use_rth => int: 0 - all data available during the time span requested
      #                     is returned, even data bars covering time intervals where the
      #                     market in question was illiquid. 1 - only data within the
      #                     "Regular Trading Hours" of the product in question is returned,
      #                     even if the time span requested falls partially or completely
      #                     outside of them.

      # ib.send_message IB::Messages::Outgoing::RequestRealTimeBars.new(
      #                  :request_id => request_id,
      #                  :contract => contract,
      #                  :bar_size => 5, # Only 5 secs bars available?
      #                  :data_type => :trades,
      #                  :use_rth => true)

#    end
  end

  #def unreq_md(ticker_id)
  #  #tkr_plant = redis.hget("md:status:#{ticker_id}", "ticker_plant")
  #  if ticker_id == "all" then
  #    @local_subs.keys.each { |id| debug "@ib.send_message :CancelRealTimeBars, :id => #{id}" }
  #    @local_subs.keys.each { |id| @ib.send_message :CancelRealTimeBars, :id => id
  #                            @local_subs.delete(id) }
  #  else
  #    tkr_plant = @mkt_subs.ticker_plant(ticker_id)
  #    debug "unreq_md(#{ticker_id}) mkt_data_server_id=#{@mkt_data_server_id}   tkr_plant=#{tkr_plant}"
  #    if (@mkt_data_server_id == tkr_plant) then
  #      debug "unreq_md(#{ticker_id})"
  #      show_info "unreq_md:Market Data UnRequest: ticker_id=#{ticker_id} on #{@mkt_data_server_id}"

  #      begin
  #        debug "@ib.send_message :CancelRealTimeBars, :id => #{ticker_id}"
  #        @ib.send_message :CancelRealTimeBars, :id => ticker_id

  #        debug "@local_subs.delete(#{ticker_id})"
  #        @local_subs.delete(ticker_id)
  #        #@mkt_subs.unsubscribe(ticker_id, "bar5s")
  #      rescue => e
  #        warn "Problem with CancelRealTimeBars"
  #        warn e.message
  #      end
  #    else
  #      $stderr.puts "Could not Cancel MktData for #{ticker_id}/#{tkr_plant} on #{@mkt_data_server_id}"
  #    end
  #  end
  #end

end
