$: << "#{ENV['ZTS_HOME']}/etc"
require "zts_config"
require_relative 'redis_helper'
require_relative 'redis_position'
#require_relative '../../lib/old/redis_position'
#require 'redis_position'
require 'launchd_helper'
require 'position_struct'
require 'json'
#require 'redis_helper'
require_relative 'amqp_sync'
require 'z_logger'

class  Position
  include LaunchdHelper
  include RedisHelper
  
  attr_accessor :side_multiplier
#  attr_accessor :pos_id
  #attr_reader :data_struct
  attr_reader :publisher

  def initialize(publisher=AmqpSync.new, logger=ZLogger.new)
    @publisher = publisher
    @logger = logger
  end
  
  def get(id)
    @id = id
    setup(RedisPosition.get(id))
  end

  def create(trade)
    lstdout "Position#create:trade=#{trade}"

    setup(trade)    
    
    init_values
    self.pos_id = next_id
    attribs = @data_struct.attributes
    lstdout "attribs=#{attribs}"
    
    RedisPosition.create(attribs)
    publish_new(@data_struct)
    @data_struct  
  end

  def setup(trade)
    @data_struct = PositionStruct.from_hash(trade)
    @side_multiplier = ((side == 'long') ? 1 : -1)
    @new_routing_key    = ZtsApp::Config::ROUTE_KEY[:position][:new]
    @close_routing_key  = ZtsApp::Config::ROUTE_KEY[:position][:closed]
  end

  def init_values
    lstdout "Position#init_values"
    self.current_risk = init_risk
    self.support      = setup_support
    self.quantity     = 0
    self.position_qty = 0
    self.realized     = 0
    self.unrealized   = 0
    self.status       = 'init'
  end
  
  def valid?
    (ticker && ticker.size > 0)
  end

  def next_id
    RedisPosition.next_id
  end
  
  def Position.open_positions
    RedisPosition.open_positions(account)
  end
  
  def update_stop_price(price)
    new_stop, new_stop_trigger = calc_stop_price(price) 
    delta = (new_stop - current_stop) * side_multiplier
    updated = false
    if (delta >= 0.05)
      self.current_stop = new_stop
      self.next_stop_trigger = new_stop_trigger
      publish_stop_price
      updated = true
    end
    updated
  end

  def calc_stop_price(current_price)
    case adjust_stop_trigger
    when 'price'
      new_stop = (current_price.to_f - side_multiplier * current_risk).round(2)
      new_stop_trigger = (current_price.to_f + side_multiplier * current_risk).round(2)
    when 'manual'
      new_stop = support.to_f -
                 side_multiplier * ((current_price.to_f < 10.0) ? 0.12 : 0.25)
      new_stop_trigger = nil
    end
    [new_stop, new_stop_trigger]
  end

  def update_support_level(level)
    args = {support: level}
    RedisPosition.set(pos_id, args)
    publish_set(args)
  end

  def publish_stop_price
    args = {current_stop: current_stop, next_stop_trigger: next_stop_trigger}
    RedisPosition.set(pos_id, args)
    publish_set(args)
  end
  
  def publish_new(pos)
    lstdout "Position(#{pos.pos_id}): publish_new(#{pos})"
    publisher.publish(pos.attributes.to_json, :routing_key => @new_routing_key, :persistent => true)
  end
  
  def publish_set(args)
    args.merge!({account: account, pos_id: pos_id})
    routing_key = ZtsApp::Config::ROUTE_KEY[:position][:update]
    
    lstdout "<- #{publisher.name}/#{routing_key} #{args}"
    publisher.publish(args.to_json, :routing_key => routing_key, :persistent => true)
  end
  
  def publish_close
    msg = {sec_id: sec_id, pos_id: pos_id}
    lstdout "Position(#{pos_id})<-(#{publisher.name}/#{@close_routing_key}/#{pos_id}) #{msg}"
    publisher.publish(msg.to_json, :message_id => pos_id, :routing_key => @close_routing_key, :persistent => true)
  end
  
  def buy(qty, price)
    lstdout "Position(#{pos_id})#buy(#{qty}, #{price})"
    lstdout "Position(#{pos_id})Buying 0 quantity, WTF" unless qty > 0
    return [quantity, 0] unless qty > 0
    over_fill = 0
    new_flag = true if (quantity == 0)
    new_qty = quantity + qty
    args = {}
lstdout "Position#buy: #{@data_struct.inspect}"
    if(side == 'long') then
      self.status = 'open'
      self.position_qty = position_qty + qty
      self.avg_entry_px = (quantity.abs * avg_entry_px + qty.abs * price) / new_qty.abs
      args['position_qty'] = position_qty
      args['avg_entry_px'] = avg_entry_px
    elsif(side == 'short') then
      self.status = 'unwind'
      if new_qty >= 0 then
        self.status = 'closed'
        args['closed_date'] = Date.today.strftime('%Y%m%d')
        over_fill = new_qty.abs
        new_qty = 0
      end
      self.realized = realized + qty.to_f * (avg_entry_px - price.to_f)
      self.unrealized = new_qty.abs * (avg_entry_px - price.to_f)
      lstdout "avg_exit_px = (#{avg_exit_px} * #{quantity} + #{price} * #{qty}) / (#{position_qty} - #{quantity} + #{qty})"
      self.avg_exit_px = (avg_exit_px * quantity + price * qty) / (position_qty - quantity + qty)
      args['realized'] = realized
      args['unrealized'] = unrealized
      args['avg_exit_px'] = avg_exit_px
    else
      raise "Position#buy:: side(#{side}) Not understood"
    end

    self.quantity = new_qty
lstdout "Position#buy:data_struct= #{@data_struct.inspect}"
    args['status'] = status
    args['quantity'] = quantity 
    args['trade_date'] = Date.today.strftime('%Y%m%d') if new_flag
lstdout "Position#buy:args= #{args.inspect}"
    RedisPosition.set(pos_id, args)
    
    publish_set(args)
    
    [new_qty, over_fill]
  end
  
  def sell(qty, price)
    lstdout "Position(#{pos_id})Selling 0 quantity, WTF" unless qty > 0
    return [quantity, 0] unless qty > 0
    over_fill = 0
    new_flag = true if (quantity == 0)
    new_qty = quantity - qty
    args = {}
    if(side == 'short') then
      self.status = 'open'
      self.position_qty = position_qty - qty
      self.avg_entry_px = (quantity.abs * avg_entry_px + qty.abs * price) / new_qty.abs
      args['position_qty'] = position_qty
      args['avg_entry_px'] = avg_entry_px
    elsif(side == 'long') then
      self.status = 'unwind'
      if(new_qty <= 0) then
        self.status = 'closed'
        args['closed_date'] = Date.today.strftime('%Y%m%d')
        over_fill = new_qty.abs
        new_qty = 0
      end
      self.realized = realized + qty.to_f * (price.to_f - avg_entry_px)
      self.unrealized = new_qty * (price.to_f - avg_entry_px)
      lstdout "avg_exit_px = (#{avg_exit_px} * #{position_qty - quantity} + #{price} * #{qty}) / (#{position_qty} - #{quantity} + #{qty})"
      self.avg_exit_px = (avg_exit_px * (position_qty - quantity) + price * qty) / 
                    (position_qty - quantity + qty)
      args['realized'] = realized
      args['unrealized'] = unrealized
      args['avg_exit_px'] = avg_exit_px
    else
      raise "Position#sell:: side(#{side}) Not understood"
    end

    self.quantity = new_qty
    args['quantity'] = quantity 
    args['status'] = status
    args['trade_date'] = Date.today.strftime('%Y%m%d') if new_flag
    RedisPosition.set(pos_id, args)

    lstdout "Position(#{pos_id})#sell  publish_set(#{args})"
    publish_set(args)
    
    [new_qty, over_fill]
  end
  
  def close
    self.status = 'closed'
    today = Date.today.strftime('%Y%m%d')
    args = {'status' => status, 'closed_dt' => today}
    RedisPosition.set(pos_id, args)
    remove_position_alerts(pos_id)
    publish_close
  end
  
  def stop_action
    (side == 'long') ? :sell : :buy
  end
  
#  def to_s
##    "id(#{id}) sec_id(#{mkt}:#{sec_id}) #{side} qty(#{quantity}/#{tgt_size})"
#    "id(#{id}) sec_id(#{mkt}:#{sec_id}) #{side} qty(#{quantity})"
#  end
  
  def to_human
    "pos(#{pos_id}) #{quantity} #{ticker}(#{sec_id}) to #{broker} #{status}"
  end

  def db_parms
    {pos_id: pos_id, setup_id: setup_id, sec_id: sec_id, side: side, 
      init_risk: init_risk, current_risk: current_risk, 
      avg_entry_px: avg_entry_px, quantity: quantity, position_qty: position_qty,
      setup_support: setup_support,  support: support,
      status: status, current_stop: current_stop, 
      setup_src: setup_src, entry_name: entry_name,
      account: account, broker: broker,
      mm_size: mm_size, mm_entry_px: mm_entry_px}
  end
  
  # getters
  def quantity;            @data_struct.quantity.to_f;       end
  def side;                @data_struct.side;                end  
  def pos_id;              @data_struct.pos_id;              end
  def status;              @data_struct.status;              end
  def setup_src;           @data_struct.setup_src;           end
  def trade_type;          @data_struct.trade_type;          end
  def account;             @data_struct.account;             end
  def mm_size;             @data_struct.mm_size;             end
  def mm_entry_px;         @data_struct.mm_entry_px;         end
  def broker;              @data_struct.broker;              end
  def sec_id;              @data_struct.sec_id;              end
  def init_risk;           @data_struct.init_risk;           end
  def position_qty;        @data_struct.position_qty.to_f;   end
  def setup_id;            @data_struct.setup_id;            end
  def ticker;              @data_struct.ticker;              end
  def entry_name;          @data_struct.entry_name;          end
  def mkt;                 @data_struct.mkt;                 end
  def next_stop_trigger;   @data_struct.next_stop_trigger;   end
  def avg_entry_px;        @data_struct.avg_entry_px.to_f;   end
  def current_risk;        @data_struct.current_risk.to_f;   end
  def realized;            @data_struct.realized.to_f;       end
  def unrealized;          @data_struct.unrealized.to_f;     end
  def avg_exit_px;         @data_struct.avg_exit_px.to_f;    end
  def adjust_stop_trigger; @data_struct.adjust_stop_trigger; end
  def setup_support;       @data_struct.setup_support;       end
  def support;             @data_struct.support;             end
  
  def current_stop
    (@data_struct.current_stop.to_f.to_i == 0) ? (side.eql?('long') ? 0 : 9999) : @data_struct.current_stop.to_f
  end
  
  # setters
  def quantity=(quantity);    @data_struct.quantity          = quantity;          end
  def side=(side);            @data_struct.side              = side;              end  
  def pos_id=(pos_id);        @data_struct.pos_id            = pos_id;            end
  def status=(status);        @data_struct.status            = status;            end
  def setup_src=(setup_src);  @data_struct.setup_src         = setup_src;         end
  def trade_type=(trade_type);  @data_struct.trade_type      = trade_type;         end
  def account=(account);      @data_struct.account           = account;           end
  def mm_size=(mm_size);      @data_struct.mm_size           = mm_size;           end
  def mm_entry_px=(mm_entry_px); @data_struct.mm_entry_px    = mm_entry_px;       end
  def broker=(broker);        @data_struct.broker            = broker;            end
  def sec_id=(sec_id);        @data_struct.sec_id            = sec_id;            end
  def init_risk=(init_risk);  @data_struct.init_risk         = init_risk;         end
  def position_qty=(position_qty); @data_struct.position_qty = position_qty.to_f; end
  def setup_id=(setup_id);    @data_struct.setup_id          = setup_id;          end
  def ticker=(ticker);        @data_struct.ticker            = ticker;            end
  def entry_name=(entry_name);@data_struct.entry_name        = entry_name;        end
  def mkt=(mkt);              @data_struct.mkt               = mkt;               end
  def next_stop_trigger=(next_stop_trigger); @data_struct.next_stop_trigger = next_stop_trigger; end
  def avg_entry_px=(avg_entry_px);   @data_struct.avg_entry_px = avg_entry_px;      end
  def current_risk=(current_risk);   @data_struct.current_risk = current_risk;      end
  def realized=(realized);           @data_struct.realized          = realized;     end
  def unrealized=(unrealized);       @data_struct.unrealized        = unrealized;   end
  def avg_exit_px=(avg_exit_px);     @data_struct.avg_exit_px    = avg_exit_px;     end
  def adjust_stop_trigger=(adjust_stop_trigger); @data_struct.adjust_stop_trigger    = adjust_stop_trigger;       end
  def current_stop=(current_stop);   @data_struct.current_stop = current_stop;      end
  def setup_support=(setup_support); @data_struct.setup_support = setup_support;    end
  def support=(support);             @data_struct.support = support;                end
end

