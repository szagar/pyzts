#!/usr/bin/env ruby
# encoding: utf-8

$: << "#{ENV['ZTS_HOME']}/lib"

require "active_record"
require "logger"
require "log_helper"
require "store_mixin"
require "s_m"
require "tags"
require "db_data_queue/message"

class Positions        < ActiveRecord::Base; end
class PositionTags     < ActiveRecord::Base; end
class LogPositions     < ActiveRecord::Base; end
class Executions       < ActiveRecord::Base; end
#class BrokerAccounts  < ActiveRecord::Base; end
class Accounts         < ActiveRecord::Base; end
class IbAccountData    < ActiveRecord::Base; end
class SmTkrs           < ActiveRecord::Base; end
class SmPrices         < ActiveRecord::Base; end
class McaData          < ActiveRecord::Base; end
class McaScan          < ActiveRecord::Base; end
class Watchlists       < ActiveRecord::Base; end
class WatchlistData    < ActiveRecord::Base; end
class Orders           < ActiveRecord::Base; end

module DbDataQueue
  Queue         = "queue:db"
  InflightQueue = "queue:db:inflight"

  class Consumer
    include LogHelper
    include Store
    #attr_reader :redis
    attr_reader :ibAccountDataFields, :accountDataFields
    attr_reader :sec_master

    def initialize
      Zts.configure { |config| config.setup }
      #@redis = RedisFactory2.new.client
      initialize_database
      @sec_master   = SM.instance
      @ibAccountDataFields = Hash.new
      @accountDataFields = Hash.new
      %w(AvailableFunds BuyingPower CashBalance
         EquityWithLoanValue ExcessLiquidity GrossPositionValue
         InitMarginReq MaintMarginReq NetLiquidation RealizedPnL UnrealizedPnL
         RegTEquity RegTMargin StockMarketValue
         AccountCode AccountReady AccountType AccruedCash AccruedDividend Cushion 
         FullAvailableFunds FullExcessLiquidity FullMaintMarginReq FullInitMarginReq  Leverage
         LookAheadAvailableFunds LookAheadExcessLiquidity LookAheadInitMarginReq LookAheadMaintMarginReq
         MoneyMarketFundValue MutualFundValue NetDividend OptionMarketValue PreviousDayEquityWithLoanValue
         SMA TotalCashBalance TotalCashValue TradingType WhatIfPMEnabled
        ).each {|e| @ibAccountDataFields[e]=true }
      @accountDataFields = {
          "CashBalance"        => "cash_balance",
          "BuyingPower"        => "buying_power",
          "StockMarketValue"   => "stock_market_value",
          "GrossPositionValue" => "position_value",
          "RealizedPnL"        => "realized_pnl",
          "UnrealizedPnL"      => "unrealized_pnl"
      }
    end
  
    def run
      while ( json_msg = redis.blpop(Queue, 0)[1])
        redis.rpush InflightQueue, json_msg
        command, params = DbDataQueue::Message.decode(json_msg)
        #msg = JSON.parse(json_msg)
        puts "command: #{command}  params: #{params}"
        (self.send command, params) ? db_success(json_msg) : db_failure(json_msg)
      end
    end

    #def method_missing(command, *args, &block)
    #  warn "DbDataQueue: command (#{command}) not known"
    #end

    def test_position_tag(data)
      position_tag(data)
    end

    def test_execution(data)
      execution(data)
    end

    private

    def initialize_database
      show_info "Connect to database env: #{ENV['ZTS_ENV']}"
      #logname = "#{Zts.conf.dir_log}/#{File.basename(__FILE__, '.rb')}.log"
      #ActiveRecord::Base.logger = Logger.new(logname)
      ActiveRecord::Base.logger = Logger.new(STDOUT)
      #ActiveRecord::Base.configurations = YAML::load(IO.read(File.dirname(__FILE__)+'/../etc/database.yml'))
      ActiveRecord::Base.configurations = YAML::load(IO.read(ENV["ZTS_HOME"]+'/etc/database.yml'))
      ActiveRecord::Base.establish_connection(ENV['ZTS_ENV'].to_sym)
      show_action "Database Connection: #{ActiveRecord::Base.connection_config}"
    end

    def nop(data)
      warn "DbDataQueue::Consumer#nop"
    end

    def position_tag(data)
      debug "position_tag(#{data})"
      pos_id = data[:pos_id]
      debug "pos_id=#{pos_id}"
      tags   = data[:tags]
      debug "tags=#{tags}"
      hash_tags(tags).each do |k,v|
        debug "position tag for pos_id=#{pos_id} #{k} -> #{v}"
        rec = PositionTags.where(pos_id: pos_id,tag: k).first_or_create
        #rec = PositionTags.find_or_create_by_pos_id_and_tag(pos_id,k)
        rec.update_attributes(value: v) if v
      end
    rescue => e
      warn "Database persister: error loading position tag: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end

    def hash_tags(tags)
      ht = Tags.new.parse(tags)
      debug "Consumer#hash_tags:  ht=#{ht}"
      ht
    end

    def mca_data(data)
      mca_tkr = data.delete(:ticker)
      date    = data.delete(:date)
      indicators = data[:indicators]
      indicators.each do |tag,value|
        rec = McaData.where(:trade_date => date, :mca_tkr => mca_tkr, :tag => tag).first_or_create
        rec.update_attribute(:value, value)
      end
    rescue => e
      warn "Database persister: error loading mca_data: => #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end

    def scan_data_add(data)
      asof = data.delete(:asof)
      total_counts = data.delete(:total_counts)
      pos_counts = data.delete(:pos_counts)
      (0..6).each do |i|
        puts "rec = McaScan.where(:asof => #{asof}, :scan_number => #{i+1}).first_or_create"
        rec = McaScan.where(:asof => asof, :scan_number => i+1).first_or_create
        rec.update_attribute(:count, total_counts[i])
        rec.update_attribute(:positive_count, pos_counts[i])
      end
    rescue => e
      warn "Database persister: error loading scan_data: => #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end

    def account_data(data)
      show_info "Account data received: #{data}"

      now = data.fetch(:ts) { Time.now.to_s }
      asof = (Time.parse now).strftime('%Y%m%d')
      show_info "ibAccountDataFields=#{ibAccountDataFields}"
      show_info "if ibAccountDataFields.has_key?(#{data[:key]}) && #{data[:value]}"
      if ibAccountDataFields.has_key?(data[:key]) && data[:value]
        show_info "Database Connection: #{IbAccountData.connection_config}"
        show_info "IbAccountData.class=#{IbAccountData.class}"
        show_info "acct = IbAccountData.find_or_create_by_broker_account_and_asof(#{data[:account]},#{asof})"
        #acct = IbAccountData.find_or_create_by_broker_account_and_asof(data[:account],asof)
        acct = IbAccountData.where(broker_account: data[:account], asof: asof).first_or_create
        show_info "acct.update_attribute(#{data[:key]}, #{data[:value]})"
        acct.update_attribute(data[:key], data[:value])
      end

      if accountDataFields.has_key?(data[:key]) && data[:value]
        #acct = Accounts.find_or_create_by_account_and_asof(data[:account],asof)
        acct = Accounts.where(account: data[:account], asof: asof).first_or_create
        acct.update_attribute(accountDataFields[data[:key]], data[:value])
      end
      true
    rescue => e
      warn "Database persister: error loading account data: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end

    def sec_data(data)
      show_info "Security data received: #{data}"
      #sec_id = sec_master.insert_update("stock",data[:sec_id],data)
      #rec = SmTkrs.find_or_create_by__sec_id(data[:sec_id])
      rec = SmTkrs.where(sec_id: data[:sec_id]).first_or_create
      #sec_id = rec.sec_id || create_sm_record(data[:ticker])
      rec.update_attributes(data)
    rescue => e
      warn "Database persister: error loading security data: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end

#    def create_sm_record(ticker)
#      raise InvalidTicker.new unless ticker_valid?(ticker)
#      sec_master.insert_update("stock",0,data)
#    end

    def ticker_valid?(ticker)
      true
    end

    def execution(data)
      data[:exec_time] = data.delete :time
      data.delete :avg_price
      rec = Executions.create(data)
      #self.send(data[:action],data[:pos_id],data[:price],
      #          data[:quantity])
      #          #data[:quantity],data[:commission]) 
    rescue => e
      warn "Database persister: error loading execution: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
    end

    def commission(data)
      show_info "Commission received: #{data}"
      pos_id = update_execution_commission(data[:exec_id],data[:commission])
      update_position_commission(pos_id,data[:commission])
    rescue => e
      warn "Database persister: error processing commission: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end

    def update_execution_commission(exec_id,commission)
      exec = Executions.find_by_exec_id!(exec_id)
      exec.commission = (exec.commission || 0.0) + commission
      exec.save
      exec.pos_id
    rescue => e
      warn "Database persister: error updating execution commission: exec_id=#{exec_id} commission=#{commission}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      raise ActiveRecord::RecordNotFound.new
    end

    def update_position_commission(pos_id,commission)
      pos = Positions.find_by_pos_id(pos_id)
      pos.commissions = (pos.commissions || 0.0) + commission
      pos.save
      true
    rescue => e
      warn "Database persister: error updating position commission: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end
 
    def order(data)
      create_order(data)
    end

    def create_order(data)
      debug "create_order(#{data})"
      data.delete(:mkt)
      data.delete(:side)
      ord = Orders.where(order_id: data[:order_id]).first_or_create
      ord.update_attributes(data)
      ord.save
      true
    rescue => e
      warn "Database persister: error loading order data: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end

    def create_position(data)
      debug "create_position(#{data})"
      debug "pos = Positions.find_or_create_by_pos_id(#{data[:pos_id]})"
      pos = Positions.where(pos_id: data[:pos_id]).first_or_create
      tags = {}
      tags[:pos_id] = data.delete(:pos_id)
      tags[:tags]   = data.delete(:tags)
      pos.update_attributes(data)
      pos.save
      position_tag(tags) 
      true
    rescue => e
      warn "Database persister: error loading position data: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end

    def update_position(data)
      pos_id = data.delete(:pos_id)
      pos = Positions.where(pos_id: pos_id).first
      #pos = Positions.find_by_pos_id(pos_id)
      pos.update_attributes(data)
      pos.save
      data.each { |k,v| 
        debug "LogPositions.create(pos_id: #{pos_id}, tag: #{k}, value: #{v})"
        id = LogPositions.create(pos_id: pos_id, tag: k, value: v)
        debug "id=#{id}"
      }
      true
    rescue => e
      warn "Database persister: error updating position data: #{data}"
      warn "#{e.class}: <#{e.message}> from <#{e.backtrace.first}>??"
      false
    end

    def watchlist_update(data)
      wlist = Watchlists.where(name: data[:name]).first_or_create
      #wlist = Watchlists.find_or_create_by(name: data[:name])
      wlist.update_attributes(asof: data[:asof]) unless (wlist.asof||0).to_i > data[:asof].to_i
      wlist.save
      wlist.id
    end

    def watchlist_add(data)
      puts "watchlist_add(#{data})"
      if (data[:ticker].size > 10) 
        warn "ticker: #{data[:ticker]} too long, skipping"
        return true
      end
      wid = Watchlists.where(name: data[:watchlist_name]).first
      #wid = Watchlists.find_by(name: data[:watchlist_name])
      rec = WatchlistData.where(watchlist_id: wid.id, asof: data[:asof], ticker: data[:ticker]).first_or_create
      #rec = WatchlistData.find_or_create_by(watchlist_id: wid.id,
      #                 asof: data[:asof], ticker: data[:ticker])
      #attr[:sec_id] = 
      #attr[:score] = data[:score] if data[:score]
      #rec.update_attributes(attr)
    end

    def remove_processed_message(message)
      redis.lrem(InflightQueue, 1, message)
    end

    def db_success(message)
      remove_processed_message(message)
    end

    def db_failure(message="")
      warn "failed to load: #{message}"
      warn "check in-flight queue: #{InflightQueue}"
    end

    def valid_integer?(number)
      number.to_s =~ /^\d+$/
    end

    def invalid_pos_id(message)
    end
  end
end
