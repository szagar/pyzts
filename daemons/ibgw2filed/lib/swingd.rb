require "my_config"
require "store_mixin"
require "bar_struct"
require "portfolio_mgr"
require "risk_mgr"
require "entry_engine"
require "money_mgr"
require "account_mgr"
require "mkt_subscriptions"
require "date_time_helper"
require "s_m"
require "json"
require "amqp_factory"
require "log_helper"
require 'db_data_queue/producer'

ResendDelay    = 4
MaxRetries     = 12
SuspensionSecs = 60

class Swingd
  include LogHelper
  include Store

  attr_reader :channel, :md_channel
  attr_reader :exchange_market, :exchange
  attr_reader :money_mgr, :at_mgr, :mkt_subs

  def initialize
    show_info "Swingd#initialize"
    @mkt_subs     = MktSubscriptions.instance
    @portf_mgr    = PortfolioMgr.instance
    @risk_mgr         = RiskMgr.new
    @portf_mgr.risk_mgr = @risk_mgr
    @entry_engine = EntryEngine.new
    @money_mgr    = MoneyMgr.new
    @account_mgr = AccountMgr.new
    @accounts    = {}
    #@at_mgr       = AutoTraderMgr.new
    @db_queue     = DbDataQueue::Producer.new
    @sec_master   = SM.instance
    @do_not_exit_list  = load_do_not_exit_list
    @do_not_enter_list = load_do_not_enter_list
    DaemonKit.logger.level = :info
  end

  def amqp_setup
    amqp = AmqpFactory.instance

    puts "AMQP params: #{amqp.params}"
    connection, @channel = amqp.channel

    puts "AMQP md_params: #{amqp.md_params}"
    md_connection, @md_channel = amqp.md_channel

    debug "@exchange_flow = channel.topic(#{Zts.conf.amqp_exch}, #{Zts.conf.amqp_exch_options})"
    @exchange_flow       = channel.topic(Zts.conf.amqp_exch,
                                         Zts.conf.amqp_exch_options)
    debug "@exchange_market = md_channel.topic(#{Zts.conf.amqp_exch_mktdata}, #{Zts.conf.amqp_exch_mktdata_options})"
    @exchange_market     = md_channel.topic(Zts.conf.amqp_exch_mktdata,
                                         Zts.conf.amqp_exch_mktdata_options)
    @exchange            = channel.topic(Zts.conf.amqp_exch,
                                         Zts.conf.amqp_exch_options)
  end

  def subscriptions
    subscribe_lvc_data
    subscribe_md_bar5s
    subscribe_md_custom_bars
    subscribe_entry
    subscribe_admin
  end

  def subscribe_entry
    routing_key = Zts.conf.rt_entry
    show_info "subscribe_entry: #{routing_key} on #{@exchange.name}"
    @channel.queue("", auto_delete: true)
            .bind(@exchange, routing_key: routing_key)
            .subscribe do |hdr,payload|
      msg = JSON.parse(payload, :symbolize_names => true)
      command = msg[:command]
      acct    = msg[:account_name]
      params  = msg[:params]
      show_info "Swingd#subscribe_entry: acct    = #{acct}"
      show_info "Swingd#subscribe_entry: command = #{command}"
      show_info "Swingd#subscribe_entry: params  = #{params}"
      entry = EntryProxy.new(params)
      puts "entry = #{entry}"
      submit_daytrade(acct,entry) if command == 'submit_daytrade'
    end
  end

  def subscribe_lvc_data
    show_info "################# LVC Data"
    routing_key = "#{Zts.conf.rt_lvc}.#.#"
    show_info "Swingd#subscribe_lvc_data: subscribe:(#{exchange_market.name}/#{routing_key})"
    md_channel.queue("", auto_delete: true)
           .bind(exchange_market, routing_key: routing_key)
           .subscribe do |hdr,msg|
      debug "got lvc data"
      hdr.routing_key[/lvc\.(.*)\.(.*)/]
      mkt,id = [$1, $2]
      data = JSON.parse(msg)
      @sec_master.insert_update(mkt,id,data)
    end
  end

  def subscribe_md_bar5s
    show_info "################# Market Data Bars"
    routing_key = "#{Zts.conf.rt_bar5s}.#.#"
    show_info "Swingd#subscribe_md_bar5s: subscribe:(#{exchange_market.name}/#{routing_key})"

    md_channel.queue("", auto_delete: true)
           .bind(exchange_market, routing_key: routing_key)
           .subscribe do |hdr,msg|
      print "*"
      show_info "Swingd#subscribe_md_bar5s: #{msg}"
      hdr.routing_key[/md.bar.5sec\.(.*)\.(.*)/]
      mkt,sec_id = [$1, $2]
      bar = BarStruct.from_hash(JSON.parse(msg, :symbolize_names => true))
      update_lvc(bar)
      check_for_exits(bar)
      check_for_entries(bar)
    end
  end

  def subscribe_md_custom_bars
    show_info "################# Market Data Custom Bars"
    routing_key = "#{Zts.conf.rt_bar_custom}.*.*.*"
    show_info "md_channel.queue('', auto_delete: true).bind(#{exchange_market.name}, routing_key: #{routing_key}).subscribe do |hdr,msg|"
    md_channel.queue("", auto_delete: true)
           .bind(exchange_market, routing_key: routing_key)
           .subscribe do |hdr,msg|
      puts "routing_key=#{hdr.routing_key}"
      hdr.routing_key[/md.bar.custom\.(.*)\.(.*)\.(.*)/]
      mkt,sec_id,secs = [$1, $2, $3]
      puts "subscribe_md_custom_bars: #{mkt}/#{sec_id}/#{secs}"
      bar = BarStruct.from_hash(JSON.parse(msg, :symbolize_names => true))
      #check_auto_traders(bar)
    end
  end

  def sod_process(parms={})
    show_action "Swingd:sod_process"
    #portf_mgr.sids_of_open_positions.each do |sid|
    #  show_action "Swingd#sod_process: request_md(#{sid})"
    #  request_md(sid)
    #end
  end

  def eod_process(parms={})
    show_action "Swingd#eod_process DO NOTHING"
  end

  def load_watchlists(parms={})
    show_action "Swingd:load_watchlists"
    @do_not_exit_list  = load_do_not_exit_list
    show_exit_watchlist
    @do_not_enter_list = load_do_not_enter_list
    show_enter_watchlist
  end

  def submit_setups(parms={})
    show_action "Swingd#submit_setups DO NOTHING"
  end

  def submit_daytrade(account_name,entry)
    show_action "Swingd:submit_daytrade(#{entry})"
    debug "Swingd#submit_daytrade limit_price=#{entry.limit_price}"
    #entry = EntryProxy.new(parms)
    debug "risk_per_share = entry.rps_exit"
    risk_per_share = entry.rps_exit
    debug "risk_per_share = #{risk_per_share}"
    unless risk_per_share > 0
      warn "risk per share is 0"
      return
    end
    acct = account(account_name)
    return unless @account_mgr.valid_trading_account?(acct)
    debug "trade = @portf_mgr.create_trade(acct,entry,risk_per_share)"
    trade = @portf_mgr.create_trade(acct,entry,risk_per_share)
    debug "order = @portf_mgr.trade_order(trade)"
    order = @portf_mgr.trade_order(trade)     # creates new position
    return unless order.valid?
    @db_queue.push(DbDataQueue::Message.new(command: "order", data: order.attributes))
    submit_order(order)
  end

  def trailing_stops(parms={})
    show_action "Swingd#trailing_stops DO NOTHING"
  end

  def start_md_monitor(parms={})
    EventMachine::add_timer(10) do     # git IB a chance to start publishing mkt data
      timer = EventMachine::PeriodicTimer.new(30) do
        now = Time.now
        fix_stale_tkrs
        if DateTimeHelper::done_for_day_with_mktdata?
          show_action "start_md_monitor: Done For Day"
          timer.cancel
        end
      end
    end
  end

  def subscribe_admin
    routing_key = Zts.conf.rt_admin
    show_info "subscribe_admin: #{routing_key} on #{exchange.name}"
    channel.queue("", auto_delete: true)
           .bind(exchange, routing_key: routing_key).subscribe do |hdr,payload|
      msg = JSON.parse(payload, :symbolize_names => true)
      command = msg[:command]
      params  = msg[:params]
      show_info "admin message: command = #{command}"
      show_info "admin message: params  = #{params}"
      begin
        self.send command, params
      rescue => e
        warn "Problem with admin msg: #{payload}"
        warn e.message
      end
    end
  end

  #####################
  private
  #####################

  def account(name)
    @accounts[name] ||= @account_mgr.get_account(name)
  end

  def load_do_not_exit_list
    File.open("#{Zts.conf.dir_wlists}/do_not_exit.txt","r").map { |rec| @sec_master.sec_lookup(rec.chomp) }.compact
  end

  def load_do_not_enter_list
    File.open("#{Zts.conf.dir_wlists}/do_not_enter.txt","r").map { |rec| @sec_master.sec_lookup(rec.chomp) }.compact
  end

  def show_exit_watchlist
    @do_not_exit_list.each { |sec_id| show_info "exit_watchlist: #{sec_id}" }
  end

  def show_enter_watchlist
    @do_not_enter_list.each { |sec_id| show_info "enter_watchlist: #{sec_id}" }
  end

  def do_not_exit_flag?(sec_id)
    @do_not_exit_list.include?(sec_id)
  end

  def scale_in?
    warn "Swingd: scale_in? needs some code here"
    false
  end

=begin
  def update_custom_bar(bar)

    c2 = (custom_bar[secs][sec_id] ||= BarStruct.new("stock","1958"))

    custom_bar[secs][bar.sec_id].high    = bar.high if bar.high > custom_bar[secs][bar.sec_id].high
    custom_bar[secs][bar.sec_id].low     = bar.low  if bar.low  > custom_bar[secs][bar.sec_id].low
    custom_bar[secs][bar.sec_id].volume += bar.volume
    custom_bar[secs][bar.sec_id].trades += bar.trades
  end

  def initialize_custom_bar(secs)
    routing_key = "Zts.conf.rt_bar_custom.#{secs}"
    timer = EventMachine::PeriodicTimer.new(secs) do
      custom_bar[secs].each do |sec_id|
        @exchange_market.publish(custom_bar[secs][sec_id].to_json, routing_key: routing_key)
        custom_bar[secs][sec_id].clear
      end
    end
  end
=end

  def request_md(sid)
    show_action "Swingd#request_md(#{sid})"
    show_info "Swingd#request_md: subscribe sid(#{sid})"
    msg = {sec_id: sid, mkt: "stock", action: "on", force: "true"}
    routing_key = Zts.conf.rt_req_bar5s
    @exchange_market.publish(msg.to_json, routing_key: routing_key)
  end

  def unrequest_md(sid)
    msg = {sec_id: sid, mkt: "stock", action: "off", force: "true"}
    routing_key = Zts.conf.rt_unreq_bar5s
    show_action "UnRequst MD for sid: #{sid}"
    @exchange_market.publish(msg.to_json, routing_key: routing_key)
  end

  def toggle_subscription(sid)
    show_action "toggle_subscription for sid: #{sid}"
    if (@mkt_subs.retry_sid(sid) > MaxRetries)
      debug "toggle_subscription: suspend MD subscription for #{sid}"
      @mkt_subs.suspend(sid)
      EM.add_timer(SuspensionSecs) do
        debug "toggle_subscription: unsuspend MD subscription for #{sid}"
        @mkt_subs.unsuspend(sid)
      end
    else
      debug "toggle_subscription: unrequest MD subscription for #{sid}"
      unrequest_md(sid)
      EM.add_timer(ResendDelay) do
        debug "toggle_subscription: request MD subscription for #{sid}"
        request_md(sid)
      end
    end
  end

  def fix_stale_tkrs(parms={})
    debug "fix_stale_tkrs"
    @mkt_subs.stale_list.each { |sid|
      puts "toggle_subscription(#{sid})"
      toggle_subscription(sid)
    }
  end

  def update_lvc(bar)
    mkt    = bar[:mkt]
    sec_id = bar[:sec_id]
    hbar = bar.attributes
    hbar.delete(:mkt)
    hbar.delete(:sec_id)
    hbar.merge!(retries: 1)
    hbar.merge!(status:  "active")
    redis_md.hmset "lvc:#{mkt}:#{sec_id}", hbar.to_a.flatten
    #20150214
    #hbar.keys.each { |k| redis_md.hset "lvc:#{mkt}:#{sec_id}", k.to_s, hbar[k] }
  end

  def check_for_exits(bar)
    debug "Swingd#check_for_exits(#{bar})"
    orders = @portf_mgr.check_for_exits(bar)
    orders.each { |o| submit_order(o) }
    

    #@risk_mgr.triggered_exits(bar,do_not_exit_flag?(bar.sec_id)).each do |order|
    #  show_action "Trailing Exit: #{order}"
    #  @portf_mgr.status_change(order.pos_id, "pending")
    #  submit_order(order)
    #end
  end

  def check_for_entries(bar)
    debug "check_for_entries(#{bar})"
    @entry_engine.triggered_entries(bar).each do |entry_id|
      show_action "entry triggered: entry_id=#{entry_id}"
      @entry_engine.status_change(entry_id, "triggered")
      @portf_mgr.trades_for_entry(entry_id).each do |trade|
        show_info "tade=#{trade.inspect}"
        #entry_engine.create_scale_in_entry(entry_id,trade.init_risk_share) if scale_in?
        order = @portf_mgr.trade_order(trade)     # creates new position
        next unless order.valid?
        @db_queue.push(DbDataQueue::Message.new(command: "order", data: order.attributes))
        submit_order(order)
      end
    end
  #rescue InvalidSetupError, InvalidEntryError => e
  #  warn e
  #  warn e.message
  end

  def submit_order(order)
    debug "Swingd#submit_order(#{order})"
    routing_key = "#{Zts.conf.rt_submit}.#{order.broker}"
    show_action "#{@exchange_flow.name}.publish("\
                "#{order.attributes}.to_json, "\
                "routing_key: #{routing_key}, "\
                "message_id: #{order.broker}, persistence: true)"
    @exchange_flow.publish(order.attributes.to_json,
                          routing_key: routing_key,
                          message_id: order.broker, persistence: true)
  end

  def check_auto_traders(bar)
    at_mgr.check_for_entries(bar).each do |entry_id|
      show_action "Swingd#check_auto_traders: entry_id=#{entry_id}"
      trade(entry_id)
    end
  end

end

