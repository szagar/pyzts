#require "redis_factory"
require "amqp_factory"
require "alert_mgr"
require 'json'
require 'entry_engine'
require 'account_mgr'
#require 'money_mgr'
require 'portfolio_mgr'
require 'risk_mgr'
require "auto_trader_mgr"
require 'db_data_queue/producer'
require 'setup_queue/consumer'
#require 'systematic'
require 'sec_master'
require 'setup_struct'
require 'fill_struct'
require 'bar_struct'
require 'ib_redis_store'
require 'mkt_subscriptions'
require "my_config"
require "log_helper"
require "zts_constants"

class Trdrd
  include LogHelper
  include ZtsConstants

  attr_reader :store, :mkt_subs, :systematic  #, :prebuys

  def initialize
    #@money_mgr    = MoneyMgr.new
    @portf_mgr    = PortfolioMgr.instance
    @acct_mgr     = AccountMgr.new
    @alert_mgr    = AlertMgr.new
    #@at_mgr       = AutoTraderMgr.new
    @entry_engine = EntryEngine.new
    @store        = IbRedisStore.new
    @mkt_subs     = MktSubscriptions.instance
    @risk_mgr     = RiskMgr.new
    @portf_mgr.risk_mgr = @risk_mgr
    @sec_master   = SecMaster.instance
    @db_queue     = DbDataQueue::Producer.new
    #@systematic   = Systematic.instance

    Zts.configure do |config|
      config.setup
    end

  end

  def amqp_setup
    connection, @channel = AmqpFactory.instance.channel
    md_connection, @md_channel = AmqpFactory.instance.md_channel
    @exchange            = @channel.topic(Zts.conf.amqp_exch,
                                         Zts.conf.amqp_exch_options)
    @exchange_db         = @channel.topic(Zts.conf.amqp_exch_db,
                                         Zts.conf.amqp_exch_options)
    @exchange_order_flow = @channel.topic(Zts.conf.amqp_exch_flow,
                                         Zts.conf.amqp_exch_options)
    @exchange_market     = @md_channel.topic(Zts.conf.amqp_exch_mktdata,
                                            Zts.conf.amqp_exch_options)
  end

  def start_cycles
    #start_post_sod_cycle
    #start_sod_cycle
    #start_eod_cycle
  end

  def subscriptions
    subscribe_alerts
    subscribe_account_balance
    subscribe_account_positions
    subscribe_setups
    subscribe_commissions
    subscribe_executions
    #subscribe_md_bar5s
    subscribe_orders
    subscribe_sm_indics
    subscribe_manual_stop_update
    subscribe_unwind_requests
    subscribe_admin
  end

  def subscribe_alerts
    ################# Alerts
    routing_key = Zts.conf.rt_alert
    show_info "subscribe_alerts: #{routing_key} on #{@exchange.name}"
    @channel.queue("", auto_delete: true)
       .bind(@exchange, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "IB Alert: #{payload.inspect}"
    end
  end

  def subscribe_account_balance
    ################# Data: Accounts
    fields = Hash.new
    %w(AvailableFunds BuyingPower CashBalance 
       EquityWithLoanValue ExcessLiquidity GrossPositionValue 
       InitMarginReq MaintMarginReq NetLiquidation RealizedPnL 
       RegTEquity RegTMargin StockMarketValue).each {|e| fields[e]=true }
    routing_key = Zts.conf.rt_acct_balance
    show_info "subscribe_account_balance: #{routing_key} on #{@exchange_db.name}"
    @channel.queue("", auto_delete: true)
       .bind(@exchange_db, routing_key: routing_key).subscribe do |payload|
      store.account_persister(payload)
      data = JSON.parse(payload)
      @db_queue.push(DbDataQueue::Message.new(command: "account_data",
                                             data: data)) if fields.include?(data["key"])
    end
  end

  def subscribe_account_positions
    ################# Data: Positions
    routing_key = Zts.conf.rt_acct_position
    show_info "subscribe_account_positions: #{routing_key} on #{@exchange_db.name}"
    @channel.queue('', auto_delete: true)
       .bind(@exchange_db, :routing_key => routing_key).subscribe do |payload|
      #print "/"
      #show_info "store.position_persister(#{payload})"
      store.position_persister(payload)
    end
  end

  def subscribe_setups
    ################# Setups
    routing_key = Zts.conf.rt_setups
    show_info "subscribe_setups: #{routing_key} on #{@exchange_order_flow.name}"
    @channel.queue("", auto_delete: true)
           .bind(@exchange_order_flow, routing_key: routing_key).subscribe do |hdr,msg|

      setup = SetupStruct.from_hash(JSON.parse(msg, :symbolize_names => true))

      no_entries =  @entry_engine.setup_entries(setup).size
      request_md(setup["sec_id"],force=false) if (no_entries > 0)
    end
  end


  def subscribe_commissions
    ################# Commissions
    routing_key = Zts.conf.rt_comm
    show_info "subscribe_commissions: #{routing_key} on #{@exchange.name}"
    @channel.queue("", auto_delete: true)
       .bind(@exchange, routing_key: routing_key).subscribe(:ack => true) do |metadata,payload|
      show_info "Received commission rpt: #{payload}"
      store.commission_persister(payload)
      #{"version":1,"exec_id":"00018037.52bc173d.01.01","commission":5.740059,"currency":"USD",
      # "realized_pnl":-160.045,"yield":null,"yield_redemption_date":0}
      comm = JSON.parse(payload)
      @db_queue.push(DbDataQueue::Message.new(command: "commission", data: comm))
      metadata.ack
      #moffice.assign_commission(comm["exec_id"], comm["commission"])
    end
  end

  def subscribe_executions
    ################# Executions
    routing_key = Zts.conf.rt_fills
    show_info "subscribe_executions: #{routing_key} on #{@exchange_order_flow.name}"
    @channel.queue("", auto_delete: true)
           .bind(@exchange_order_flow, routing_key: routing_key)
           .subscribe(:ack => true) do |metadata, payload|
      data = JSON.parse(payload)
      show_info "Execution Received: #{data}"
      fill = FillStruct.from_hash(data)
      store.execution_persister(data)
      metadata.ack

      @db_queue.push(DbDataQueue::Message.new(command: "execution", data: data))
      #moffice.allocate(fill)
      show_info fill.to_human
      debug "Execution: #{fill.inspect}"
      unless fill.pos_id.to_i > 0
        warn "Could NOT find position for execution: #{fill.inspect}"
        next
      end
      pos = @portf_mgr.send(fill.action, fill.pos_id,  fill.quantity,
                            fill.price, fill.commission||0.0)
      debug "Trdrd#subscribe_executions: class of pos is #{pos.class}"
      @portf_mgr.set_target_exit(pos)
      @risk_mgr.update_trailing_stop(fill.pos_id,fill.price)   # 20150604
    end
  end

  def subscribe_unwind_requests
    routing_key = Zts.conf.rt_unwind
    show_info "subscribe_unwind_requests: #{routing_key} on #{@exchange.name}"
    @channel.queue("", auto_delete: true)
       .bind(@exchange, {routing_key: routing_key}).subscribe(:ack => true) do |metadata,msg|
      data = JSON.parse(msg)
      case data["command"]
      when "unwind"
        pos_id = data["pos_id"]
        order = @portf_mgr.unwind_order(pos_id)
        if order.valid?
          show_action "Unwind Position ##{pos_id} order:#{order.attributes}"
          routing_key = "#{Zts.conf.rt_submit}.#{order.broker}"
          @exchange_order_flow.publish(order.attributes.to_json,
                                      routing_key: routing_key,
                                      message_id: order.broker, persistence: true)
        end
      else
        warn "Command: #{data['command']} NOT recognized: #{data}"
      end
      metadata.ack
    end
  rescue => e
    warn e.message
    warn order.attributes
  end

  def subscribe_md_ticks
    ################# Market Data Ticks
    routing_key = ""
    @channel.queue("", auto_delete: true).bind(@exchange_market, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "Received tick: #{payload.inspect}"
    end
  end

  def subscribe_orders
    ################# Status:Orders
    routing_key = Zts.conf.rt_open_order
    show_info "subscribe_orders: #{routing_key} on #{@exchange_db.name}"
    @channel.queue("", auto_delete: true).bind(@exchange_db, routing_key: routing_key).subscribe do |payload|
      debug "Received order status: #{payload.inspect}"
      data = JSON.parse(payload)
      store.order_persister(data)
    end

    routing_key = Zts.conf.rt_order_status
    show_info "subscribe_orders: #{routing_key} on #{@exchange_db.name}"
    @channel.queue("", auto_delete: true).bind(@exchange_db, routing_key: routing_key).subscribe(:ack => true) do |metadata,payload|
      data = JSON.parse(payload)
      show_info "order state: brkr_ref:#{data["broker_ref"]} local:#{data["local_id"]} stat:#{data["status"]} "\
                "#{data["filled"]}/#{data["remaining"]} @#{data["average_fill_price"]} perm#:#{data["perm_id"]}"
      debug "store.order_persister(#{data})"
      pos_id = store.order_persister(data)
      debug "Trdrd, from order_persister, pos_id=#{pos_id}"
      order_status = data['status']
      #warn "Order status: #{order_status} NOT coded for!" unless %w(Filled Cancelled Submitted PendingSubmit).include?(order_status)
      OrderStatus.fetch(order_status.to_sym) {warn "Order status: #{order_status} NOT coded for!"}
      @portf_mgr.release_excess_escrow(pos_id) if %w(Filled Cancelled).include?(order_status)
      warn "PendingCancel for order for position #{pos_id}" if (order_status == "PendingCancel")
      metadata.ack
    end
  end

  def subscribe_sm_indics
    ################# SM Indicatives
    @channel.queue('sm_indics').subscribe(:ack => true) do |hdr, msg|
      debug "Received SM Indics : #{msg.inspect}"
      hdr.ack
      indics = SmIndics.from_hash(JSON.parse(msg))
      sec_master.update_indics(indics)
    end
  end

  def subscribe_manual_stop_update
    routing_key = Zts.conf.rt_manual_stop
    show_info "subscribe_manual_stop_update: #{routing_key} on #{@exchange_order_flow.name}"
    @channel.queue("", auto_delete: true)
           .bind(@exchange_order_flow, routing_key: routing_key).subscribe(:ack => true) do |metadata,pos_id|
      show_info "Received Manual Stop : #{pos_id}"
      @risk_mgr.update_trailing_stop(pos_id)
      metadata.ack
    end
  end

  def subscribe_admin
    routing_key = Zts.conf.rt_admin
    show_info "subscribe_admin: #{routing_key} on #{@exchange.name}"
    @channel.queue("", auto_delete: true)
           .bind(@exchange, routing_key: routing_key).subscribe do |hdr,payload|
      msg = JSON.parse(payload, :symbolize_names => true)
      command = msg[:command]
      params  = msg[:params]
      show_info "admin message: command = #{command}"
      show_info "admin message: params  = #{params}"
      begin
        self.send command, params
      rescue => e
        warn e.message
        #puts "Error during admin msg processing: #{$!}"
        #puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        #puts "this line was reached by #{caller.join("\n")}"
      end
    end
  end

  def test_stub
    eod_process
  end

  ####################
  private
  ####################

  def setup_srcs
    return @setup_srcs if @setup_srcs
    @setup_srcs = @acct_mgr.accounts.map do |account|
      account.setups
    end
    debug "setup_srcs: 1 : #{@setup_srcs}"
    @setup_srcs.flatten!
    debug "setup_srcs: 2 : #{@setup_srcs}"
    @setup_srcs.uniq!
    debug "setup_srcs: 3 : #{@setup_srcs}"
    @setup_srcs
  end

  def eligible_setup_src?(setup_src)
    debug "eligible_setup_src?(#{setup_src})"
    debug "eligible_setup_src?: setup_srcs=#{setup_srcs}"
    setup_srcs.include?(setup_src)  || setup_srcs.include?("all")
  end  

  def intraday_process
    intraday_timer = EM::PeriodicTimer.new(5*60) do
      @acct_mgr.accounts.each do |account|
        #@portf_mgr.mark_positions(account.account_name)
      end
      intraday_timer.cancel unless DateTimeHelper::market_open?
    end
  end

#  def start_eod_cycle
#    secs2start = DateTimeHelper::calc_secs_to_eod
#    show_info "Time until next EOD process .... #{DateTimeHelper::secs2elapse(secs2start)}"
#    EM.add_timer(secs2start) do
#      eod_process
#      sleep 1
#      start_eod_cycle
#    end
#  end

  def sod_process(parms={})
    show_action "Trdrd#sod_process"
    @portf_mgr.sids_of_open_positions.each do |sid|
      show_action "Trdrd#sod_process:  positions request_md(#{sid})"
      request_md(sid)
    end
    #at_mgr.sec_ids.each do |sid|
    #  request_md(sid)
    #  show_action "Trdrd#sod_process: auto trading request_md(#{sid})"
    #end
  end

  def md_unsubscribe(parms="all")
    show_action "md_unsubscibe"
    #unsubscribe_md(parms)
    unsubscribe_md("all")
  end


  def submit_setups(parms="all")
    debug "Trdrd#submit_setups(#{parms})"
    queue = parms[:queue]
    q ||= SetupQueue::Consumer.new(queue)
    while (msg = q.pop)
      debug "Trdrd#submit_setups: msg=#{msg}"
      setup = SetupStruct.from_hash(msg)
      debug "Trdrd#submit_setups: setup=#{setup}"
      next unless eligible_setup_src?(setup.setup_src)
      no_entries =  @entry_engine.setup_entries(setup).size
      request_md(setup["sec_id"],force=false) if (no_entries > 0)
    end
  end

  def eod_process(parms={})
    show_info "eod_process"
    unsubscribe_md("all")
    @alert_mgr.cleanup("EntryEngine")
    @acct_mgr.accounts.each do |account|
      show_action "run eod_process for account: #{account}"
      @portf_mgr.cancel_pending_positions(account.account_name)
      @portf_mgr.mark_positions(account.account_name)
    end
  end

  def submit_daytrade(parms={})
    show_action "Trdrd#submit_daytrade DO NOTHING"
  end

  def start_md_monitor(parms={})
    show_action "Trdrd#start_md_monitor DO NOTHING"
  end

  def load_watchlists(parms={})
    show_action "Trdrd#load_watchlists DO NOTHING"
  end

  def nightly_process
    show_info "nightly_process"
    #@acct_mgr.accounts.each do |account|
    #  @portf_mgr.update_wave_support(account.account_name)
    #end
    @alert_mgr.cleanup("EntryEngine")
  end

  #def send_systematic_setups(filter="")
  #  show_action "Creating systematic setups, filter=#{filter}..."
  #  routing_key = Zts.conf.rt_setups
  #  systematic.setups(filter).each do |setup|
  #    show_info "send_systematic_setups, setup: #{setup}, #{setup.class}"
  #    @exchange.publish(setup.to_json, routing_key: routing_key)
  #  end
  #end

  def log_level(params)
    show_action "log_level(#{params})"
    show_action "change log level #{$zts_log_level} -> #{params[:log_level]}"
    $zts_log_level = params[:log_level].to_i
  end

  def update_trailing_stop_type(params)
    show_action "update_trailing_stop_type(#{params})"
    pos_id = params[:pos_id]
    type   = params[:trailing_stop_type]
    return unless @portf_mgr.position_is_open?(pos_id)
    position = @portf_mgr.position(pos_id)
    position.update_trailing_stop_type(type)
  end

  def update_atr_factor(params)
    show_action "update_atr_fator(#{params})"
    pos_id = params[:pos_id]
    factor = params[:atr_factor]
    return unless @portf_mgr.position_is_open?(pos_id)
    position = @portf_mgr.position(pos_id)
    position.update_atr_factor(factor)
  end

  def timed_exits(params)
    show_action "Trdrd#timed_exits(#{params})"
    @risk_mgr.timed_exits.each do |order|
      show_action "Trdrd#timed_exits: Timed Exit: #{order}"
      routing_key = "#{Zts.conf.rt_submit}.#{order.broker}"
      @exchange_order_flow.publish(order.attributes.to_json,
                                  routing_key: routing_key,
                                  message_id: order.broker, persistence: true)
    end
    show_action "Trdrd#timed_exits  done"
  end

  def trailing_stops(params)
    show_action "Update trailing stops. params: #{params}"
    pos_ids = []
    pos_ids << params[:pos_id] if params.has_key?(:pos_id)
    pos_ids << @portf_mgr.open_positions(params[:account_name]) if params.has_key?(:account_name)
    pos_ids << @acct_mgr.accounts.map { |account| @portf_mgr.open_positions(account.account_name) } if params.fetch(:all_accounts,false) == true
    pos_ids.flatten.each do |pos_id|
      show_info "@risk_mgr.update_trailing_stop(#{pos_id})"
      @risk_mgr.update_trailing_stop(pos_id)
    end
  end

  def update_support_level(params)
    puts "Trdrd#update_support_level(#{params})}"
    pos_id = params[:pos_id]
    level  = params[:support].to_f
    return unless @portf_mgr.position_is_open?(pos_id)
    position = @portf_mgr.position(pos_id)
    position.update_support_level(level.to_f)
  end

  def request_md(sid,force=false)
    show_action "Trdrd#request_md(#{sid})"
    if (mkt_subs.add_sid(sid) || force)
      show_info "Trdrd#request_md: subscribe sid(#{sid})"
      msg = {sec_id: sid, mkt: "stock", action: "on", force: "true"}
      routing_key = Zts.conf.rt_req_bar5s
      @exchange_market.publish(msg.to_json, routing_key: routing_key)
    else
      show_info "DID NOT subscribe sid(#{sid})"
    end
  end

  def unrequest_md(sid)
    show_action "Trdrd#unrequest_md(#{sid})"
    msg = {sec_id: sid, mkt: "stock", action: "off", force: "true"}
    routing_key = Zts.conf.rt_unreq_bar5s
    show_info "#{@exchange_market.name}.publish(#{msg}.to_json, routing_key: #{routing_key})"
    @exchange_market.publish(msg.to_json, routing_key: routing_key)
  end

  def unsubscribe_md(sec_id="all")
    debug "Trdrd#unsubscribe_md(#{sec_id})"
    sids = (sec_id == "all") ? mkt_subs.sids : Array(sec_id) 
    debug "Trdrd#unsubscribe_md sids=#{sids}"
    unrequest_md(sec_id) if sec_id == "all"
    sids.each do |sec_id|
      unrequest_md(sec_id) unless sec_id == "all"
      mkt_subs.unsubscribe(sec_id)
    end
  end

end

