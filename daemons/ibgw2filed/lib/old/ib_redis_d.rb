#require "redis_factory"
require "amqp_factory"
require 'ib_redis_store'
require "my_config"

class IbRedisD
  attr_reader :persister
  attr_reader :channel
  attr_reader :exchange_db, :exchange_order_flow, :exchange_market

  def initialize
    @persister    = IbRedisStore.new
    @mkt_subs     = MktSubscriptions.instance
    @rmgr         = RiskMgr.instance
    @sec_master   = SecMaster.instance

    Zts.configure do |config|
      config.setup
    end

  end

  def amqp_setup
    connection, @channel = AmqpFactory.instance.channel
    @exchange_db         = channel.topic(Zts.conf.amqp_exch_db,
                                         Zts.conf.amqp_exch_options)
    @exchange_order_flow = channel.topic(Zts.conf.amqp_exch_flow,
                                         Zts.conf.amqp_exch_options)
    @exchange_market     = channel.topic(Zts.conf.amqp_exch_mktdata,
                                         Zts.conf.amqp_exch_options)
  end

  def subscribe_alerts
    ################# Alerts
    routing_key = Zts.conf.rt_alert
    channel.queue("", auto_delete: true)
       .bind(exchange_market, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "IB Alert: #{payload.inspect}"
    end
  end

  def subscribe_account_balance
    ################# Data: Accounts
    routing_key = Zts.conf.rt_acct_balance
    channel.queue("", auto_delete: true)
       .bind(exchange_db, routing_key: routing_key).subscribe do |payload|
      #DaemonKit.logger.debug "Received account message: #{payload.inspect}"
      print "-"
      puts "persister.account_persister(payload)"
      persister.account_persister(payload)
    end
  end

  def subscribe_account_positions
    ################# Data: Positions
    #routing_key = ZtsApp::Config::ROUTE_KEY[:data][:account][:position]
    routing_key = Zts.conf.rt_acct_position
    channel.queue('', auto_delete: true)
       .bind(exchange_db, :routing_key => routing_key).subscribe do |payload|
      #DaemonKit.logger.debug "Received position message: #{payload.inspect}"
      print "/"
      puts "persister.position_persister(payload)"
      persister.position_persister(payload)
    end
  end

  def subscribe_setups
    ################# Setups
    #channel.queue('setups').subscribe(:ack => true) do |hdr, msg|
    #  hdr.ack
    routing_key = Zts.conf.rt_setups
    channel.queue("", auto_delete: true)
       .bind(exchange_order_flow, routing_key: routing_key).subscribe do |hdr,msg|

      DaemonKit.logger.info "Received setup: #{msg.inspect}"
      setup = SetupStruct.from_hash(JSON.parse(msg, :symbolize_names => true))
      DaemonKit.logger.debug "setup created"

      begin
      entry_engine.setup_entries(setup).each do |entry_id|
        DaemonKit.logger.debug "entry_id=>#{entry_id}"
        DaemonKit.logger.debug "call money_manger for trades"
        money_mgr.trades_for_entry(entry_id).each do |trade|  # determine init_risk, size
          DaemonKit.logger.debug "trade each: #{trade.attributes}"
          order = portf_mgr.trade_order(trade)
          next unless order.valid?
          #routing_key = "#{ZtsApp::Config::ROUTE_KEY[:order_flow][:order]}.#{order.broker}"
          routing_key = "#{Zts.conf.rt_submit}.#{order.broker}"
          DaemonKit.logger.info "Submit:#{order.to_human}"
          DaemonKit.logger.debug "#{exchange_order_flow.name}.publish("\
                                 "order.attributes.to_json, routing_key: #{routing_key}, "\
                                 "message_id: #{order.broker}, persistence: true)"
          exchange_order_flow.publish(order.attributes.to_json, routing_key: routing_key,
                                      message_id: order.broker, persistence: true)
        end
      end
      rescue InvalidSetupError, InvalidEntryError => e
        DaemonKit.logger.exception( e )
        DaemonKit.logger.debug "Exeception ... 1"
        DaemonKit.logger.warn e.message
      end

      if entry_engine.market_data_subscription?(setup.ticker)
        DaemonKit.logger.info "MD subscribe: ticker=#{setup.ticker}(#{setup.sec_id})"
        if mkt_subs.add_sid(setup.sec_id)
          msg = {sec_id: setup.sec_id, mkt: setup.mkt||"stock", action: "on"}
          routing_key = Zts.conf.rt_req_bar5s
          DaemonKit.logger.debug "#{exchange_market.name}.publish(#{msg}.to_json, "\
                                 "routing_key: #{routing_key})"
          exchange_market.publish(msg.to_json, routing_key: routing_key)
        end
      end
    end
  end

  def subscribe_commissions
    ################# Commissions
    #routing_key = ZtsApp::Config::ROUTE_KEY[:data][:commission]
    routing_key = Zts.conf.rt_comm
    channel.queue("", auto_delete: true)
       .bind(exchange_market, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.debug "Received commission rpt: #{payload.inspect}"
    end
  end

  def subscribe_executions
    ################# Executions
    routing_key = Zts.conf.rt_fills
    channel.queue("", auto_delete: true)
       .bind(exchange_order_flow, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "Execution Received."
      fill = FillStruct.from_hash(JSON.parse(payload))
      DaemonKit.logger.info fill.to_human
      DaemonKit.logger.debug "Execution: #{fill.inspect}"
      portf_mgr.send(fill.action, fill.pos_id,  fill.quantity,
                     fill.price, fill.commission||0.0)
      rmgr.update_trailing_stop(fill.pos_id)
    end
  end

  def subscribe_md_bar5s
    puts "subscribe_md_bar5s"
    ################# Market Data Bars
    routing_key = "#{Zts.conf.rt_bar5s}.#.#"
    channel.queue("", auto_delete: true)
       .bind(exchange_market, {routing_key: routing_key}).subscribe do |msg|
      print "*"
      #hdr.ack
      bar = BarStruct.from_hash(JSON.parse(msg, :symbolize_names => true))
      #DaemonKit.logger.debug "Received market data: #{bar.to_human}"

      #DaemonKit.logger.debug "Check for exits."
      rmgr.triggered_exits(bar).each do |order|
        DaemonKit.logger.info "Trailing Exit: #{order}"
        routing_key = "#{Zts.conf.rt_submit}.#{order.broker}"
        exchange_order_flow.publish(order.attributes.to_json,
                                    routing_key: routing_key,
                                    message_id: order.broker, persistence: true)
      end

      #DaemonKit.logger.debug "Check for entries."
      begin
        entry_engine.triggered_entries(bar).each do |entry_id|
          money_mgr.trades_for_entry(entry_id).each do |trade| # init_risk, size
            order = portf_mgr.trade_order(trade)
            next unless order.valid?
            routing_key = "#{Zts.conf.rt_submit}.#{order.broker}"
            DaemonKit.logger.debug "#{exchange_order_flow.name}.publish("\
                                   "order.attributes.to_json, "\
                                   "routing_key: #{routing_key}, "\
                                   "message_id: #{order.broker}, persistence: true)"
            exchange_order_flow.publish(order.attributes.to_json,
                                        routing_key: routing_key,
                                        message_id: order.broker, persistence: true)
          end
        end
      rescue InvalidSetupError, InvalidEntryError => e
        DaemonKit.logger.exception( e )
        #DaemonKit.logger.warn e.message
      end
    end
  end

  def subscribe_md_ticks
    ################# Market Data Ticks
    routing_key = ""
    channel.queue("", auto_delete: true).bind(exchange_market, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "Received tick: #{payload.inspect}"
    end
  end

  def subscribe_orders
    ################# Status:Orders
    routing_key = Zts.conf.rt_open_order
    channel.queue("", auto_delete: true).bind(exchange_db, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "*******Received order status: #{payload.inspect}"
    end
    routing_key = Zts.conf.rt_order_status
    channel.queue("", auto_delete: true).bind(exchange_db, routing_key: routing_key).subscribe do |payload|
      DaemonKit.logger.info "*******Received order state: #{payload.inspect}"
      #portf_mgr.release_position_escrow(ref_id: order_status.perm_id) if order_status == "Filled"
      #portf_mgr.release_position_escrow(ref_id: order_status.perm_id) if order_status == "Cancelled"
    end
  end

  def subscribe_sm_indics
    ################# SM Indicatives
    channel.queue('sm_indics').subscribe(:ack => true) do |hdr, msg|
      DaemonKit.logger.debug "Received SM Indics : #{msg.inspect}"
      hdr.ack
      indics = SmIndics.from_hash(JSON.parse(msg))
      sec_master.update_indics(indics)
      rmgr.update_trailing_stops(indics)
    end
  end
end

