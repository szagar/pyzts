$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require "zts_config"
require "redis_account"
require "account_struct"
require 'json'
require 'launchd_helper'
require 'amqp_sync'
require 'z_logger'
require 'log_helper'
require 'zts_constants'

class Account
  include LaunchdHelper
  include LogHelper
  include ZtsConstants

  attr_reader :publisher, :logger
  attr_reader :data_struct

  def initialize(publisher=AmqpSync.new, logger=ZLogger.new)
    @publisher = publisher
    @logger = logger
    #@close_routing_key  = ZtsApp::Config::ROUTE_KEY[:account][:closed]
  end

  def get(name)
    setup(RedisAccount.get(name))
    self
  end

#  def self.get(*args, &block)
#    instance = allocate
#    instance.my_initialize(*args, &block)
#    instance
#   @new_routing_key    = ZtsApp::Config::ROUTE_KEY[:account][:new]
#   @close_routing_key  = ZtsApp::Config::ROUTE_KEY[:account][:closed]
# end

#  def create(args)
#    args[:account_id] = id
#    @name = args[:name]
#    if (hsh = RedisAccount.get(name)).empty? then
#      RedisAccount.create(args)
#      publish_new(args)      
#    end
#    setup(RedisAccount.get(name))
#    
#  end

  def create(args)
    setup(args)

    init_values
    self.account_id = next_id
    attribs = @data_struct.attributes
    #lstdout "attribs=#{attribs}"

    if (hsh = RedisAccount.get(name)).empty? then
      RedisAccount.create(attribs)
      publish_new(@data_struct.attributes)
    end
    @data_struct
  end

  def setup(trade)
    @data_struct = AccountStruct.from_hash(trade)
    #@new_routing_key    = ZtsApp::Config::ROUTE_KEY[:position][:new]
    #@close_routing_key  = ZtsApp::Config::ROUTE_KEY[:position][:closed]
  end

  def init_values
    self.sharpe_ratio = 0
    self.reliability  = 0
  end

  def next_id
    RedisAccount.next_id
  end
  
  def publish_new(args)
    new_routing_key ||= ZtsApp::Config::ROUTE_KEY[:account][:new]
    
    lstderr "<-(#{publisher.name}).publish(#{args}, :routing_key => #{new_routing_key})"
    publisher.publish(args.to_json, :routing_key => new_routing_key)
  end
  
  
  def add_setup(setup)
    RedisAccount.add_setup(name, setup)
  end
  
  def rm_setup(setup)
    RedisAccount(name, setup)
  end
  
  def setups
    RedisAccount.setups(name)
  end

  # refactor out
  def dollar_pos
    #puts "Account#dollar_pos: cash=#{cash}  position_percent=#{position_percent}"
    case equity_model
    when 'DRM'
      (risk_dollars || 0).to_f
    when 'CEM'
      cash.to_f * position_percent.to_f / 100.0
    when 'TEM'
      cash.to_f * position_percent.to_f / 100.0
    when 'RTEM'
      cash.to_f * position_percent.to_f / 100.0
    else
      lstderr "WARNING: equit_model: #{equity_model} not known"
    end
  end

  def cost_positions
    (RedisAccount.open_positions(name).inject(0) { |cost, p|
      lstdout "Account#cost_positions:p=#{p}"
      lstdout "#{cost} + (#{p['position_qty']} * #{p['avg_entry_px']}) + #{p['commissions']}"
      cost + (p['position_qty'].to_f * p['avg_entry_px'].to_f) + p['commissions'].to_f
    }).to_f
  end

  def proceeds_positions
    (RedisAccount.open_positions(name).inject(0) { |proceeds, p| proceeds + p['realized'].to_f }).to_f
  end

  def balance
    net_deposits - cost_positions + proceeds_positions
  end

  def locked_amount
    RedisAccount.calc_locked_amount(name)
    RedisAccount.getter(name, 'locked_amount').to_f
  end
  
  def risk_dollars
    (RedisAccount.getter(name, 'risk_dollars') || 0).to_f
  end

  # Defined Risk Model
  def DRM_risk_dollars
    risk_dollars 
  end

  # Core Equity Model
  def CEM_risk_dollars
    balance * position_percent / 100.0
  end

  # Total Equity Model
  def TEM_risk_dollars
    (balance + equity_value) * position_percent / 100.0
  end

  # Reduced Total Equity Model
  def RTEM_risk_dollars
    track "Account#RTEM_risk_dollars: balance=#{balance} locked_amount=#{locked_amount} position_percent=#{position_percent}"
    (balance + locked_amount) * position_percent / 100.0
  end

  def open_position_ids
    RedisAccount.open_position_ids(name)
  end

  def open_positions
    RedisAccount.open_positions(name)
  end

  def equity_value
    (RedisAccount.getter(name, 'equity_value') || 0).to_f
  end

  def equity_with_loan_value 
    (balance + equity_value).round(2)
  end

  def initial_margin(amount=0.0)
    INITIAL_MARGIN * (equity_value + amount)
  end

  def maintenance_margin
    MAINTENANCE_MARGIN * equity_value
  end

  def available_funds( amount = 0.0 )
    alert "Account#available_funds(#{amount}): #{name} #{equity_with_loan_value}(EwLV) - #{initial_margin(amount)}(IM)"
    equity_with_loan_value - initial_margin(amount)
  end

  def funds_available?( amount )
    track "Account#funds_available: available_funds(#{amount}) = #{available_funds(amount)}"
    available_funds( amount ) >= 0.0
  end

  def excess_liquidity
    equity_with_loan_value - maintenance_margin
  end

  def db_parms
    { id: account_id, name: name, money_mgr: money_mgr, position_percent: position_percent, 
      cash: cash, net_deposits: net_deposits, core_equity: core_equity, available_funds: available_funds,
      locked_amount: locked_amount, atr_factor: atr_factor, equity_model: equity_model,
      broker: broker, realized: realized, unrealized: unrealized, 
      no_trades: no_trades, no_trades_today: no_trades_today, no_open_positions: no_open_positions,
      reliability: reliability, 
      expectancy: expectancy, sharpe_ratio: sharpe_ratio, 
      vantharp_ratio: vantharp_ratio, maxRp: maxRp, maxRm: maxRm, 
      date_first_trade: date_first_trade, date_last_trade: date_last_trade, 
      status: status, risk_dollars: risk_dollars
    }
  end
  
  # getters
  def name;               @data_struct.name;                    end
  def account_id;         @data_struct.account_id;              end
  def money_mgr;          @data_struct.money_mgr;               end
  def position_percent;   @data_struct.position_percent.to_f;   end
  def cash;               @data_struct.cash.to_f;               end
  def net_deposits;       @data_struct.net_deposits.to_f;       end
  def core_equity;        @data_struct.core_equity.to_f;        end
  def equity_value;       @data_struct.equity_value.to_f;       end
  #def locked_amount;      @data_struct.locked_amount.to_f;      end
  def atr_factor;         @data_struct.atr_factor.to_f;         end
  def min_shares;         @data_struct.min_shares.to_i;         end
  def lot_size;           @data_struct.lot_size.to_i;           end
  def equity_model;       @data_struct.equity_model;            end
  def broker;             @data_struct.broker;                  end
  def broker_AccountCode; @data_struct.broker_AccountCode;      end
  def no_trades;          @data_struct.no_trades.to_i;          end
  def no_trades_today;    @data_struct.no_trades_today.to_i;    end
  def no_open_positions;  @data_struct.no_open_positions.to_i;  end
  def risk_dollars;       @data_struct.risk_dollars.to_f;       end
  def reliability;        @data_struct.reliability.to_f;        end
  def expectancy;         @data_struct.expectancy.to_f;         end
  def sharpe_ratio;       @data_struct.sharpe_ratio.to_f;       end
  def vantharp_ratio;     @data_struct.vantharp_ratio.to_f;     end
  def realized;           @data_struct.realized.to_f;           end
  def unrealized;         @data_struct.unrealized.to_f;         end
  def maxRp;              @data_struct.maxRp.to_f;              end
  def maxRm;              @data_struct.maxRm.to_f;              end
  def date_first_trade;   @data_struct.date_first_trade;        end
  def date_last_trade;    @data_struct.date_last_trade ;        end
  def status;             @data_struct.status;                  end

  #setters
  def name=(name);                             @data_struct.name=name;                             end
  def account_id=(account_id);                 @data_struct.account_id=account_id;                 end
  def money_mgr=(money_mgr);                   @data_struct.money_mgr=money_mgr;                   end
  def position_percent=(position_percent);     @data_struct.position_percent=position_percent;     end
  def cash=(cash);                             @data_struct.cash=cash;                             end
  def net_deposits=(net_deposits);             @data_struct.net_deposits=net_deposits;             end
  def core_equity=(core_equity);               @data_struct.core_equity=core_equity;               end
  def equity_value=(equity_value);             @data_struct.equity_value=equity_value;             end
  def locked_amount=(locked_amount);           @data_struct.locked_amount=locked_amount;           end
  def atr_factor=(atr_factor);                 @data_struct.atr_factor=atr_factor;                 end
  def min_shares=(min_shares);                 @data_struct.min_shares=min_shares;                 end
  def lot_size=(lot_size);                     @data_struct.lot_size=lot_size;                     end
  def equity_model=(equity_model);             @data_struct.equity_model=equity_model;             end
  def broker=(broker);                         @data_struct.broker=broker;                         end
  def broker_AccountCode=(broker_AccountCode); @data_struct.broker_AccountCode=broker_AccountCode; end
  def number_positions=(number_positions);     @data_struct.number_positions=number_positions;     end
  def risk_dollars=(risk_dollars);             @data_struct.risk_dollars=risk_dollars;             end
  def reliability=(reliability);               @data_struct.reliability=reliability;               end
  def expectancy=(expectancy);                 @data_struct.expectancy=expectancy;                 end
  def sharpe_ratio=(sharpe_ratio);             @data_struct.sharpe_ratio=sharpe_ratio;             end
  def vantharp_ratio=(vantharp_ratio);         @data_struct.vantharp_ratio=vantharp_ratio;         end
  def realized=(realized);                     @data_struct.realized=realized;                     end
  def unrealized=(unrealized);                 @data_struct.unrealized=unrealized;                 end
  def maxRp=(maxRp);                           @data_struct.maxRp=maxRp;                           end
  def maxRm=(maxRm);                           @data_struct.maxRm=maxRm;                           end
  def date_first_trade=(date_first_trade);     @data_struct.date_first_trade=date_first_trade;     end
  def date_last_trade=(date_last_trade);       @data_struct.date_last_trade=date_last_trade;       end
  def status=(status);                         @data_struct.status=status;                         end
end

#  AccountStruct.members.each do |name|
#    define_method("#{name}=") do |val|
#      puts "def #{name}=(#{name});        @data_struct.#{name}=#{name};   end   =>was set to #{val}"
#      #instance_variable_set("@data_struct.#{name}", val)
#    end
#  end

