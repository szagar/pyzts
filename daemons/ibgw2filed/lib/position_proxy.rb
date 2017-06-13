$: << "#{ENV['ZTS_HOME']}/etc"

require 'date'
require 'position_store'
require "last_value_cache"
require "exit_mgr"
require "zts_constants"
require "db_data_queue/producer"
require 'date_time_helper'
require 'log_helper'

class InvalidStopLoss < StandardError; end

class  PositionProxy
  include LogHelper
  include ZtsConstants
  
  attr_reader :pos_id, :exit_mgr, :db_queue

  def initialize(params, persister=PositionStore.instance)
    #debug "PositionProxy#initialize(#{params})"
    @store = persister
    @db_queue    = DbDataQueue::Producer.new
    @lvc         = LastValueCache.instance
    @exit_mgr    = ExitMgr.instance
    @pos_id      = params.fetch(:pos_id) {create_position(params)}
    @pos_id      = create_position(params) unless MiscHelper::valid_id?(@pos_id)
    #debug "PositionProxy#initialize done"
  end
  
  def self.exists?(pos_id)
    PositionStore.instance.exists?(pos_id)
  end

  def is_open?
    @store.getter(pos_id,"status") == "open"
  end

  def is_closed?
    @store.getter(pos_id,"status") == "closed"
  end

  def create_position(params)
    show_action "create_position: #{params[:account_name]}/#{params[:broker]} #{params[:ticker]}(#{params[:sec_id]}) pos risk:#{params[:init_risk_position]} risk share:#{params[:init_risk_share]} size:#{params[:mm_size]}"
    debug "PositionProxy#create_position(#{params})"
    debug "=======4 PositionProxy#create_position(#{params[:account_name]}) trailing_stop_type=#{params[:trailing_stop_type]}"
    set_position_defaults(params)
    @pos_id = @store.create(params)
    db_queue.push(DbDataQueue::Message.new(command: "create_position",
             data: {pos_id: pos_id, sec_id: sec_id, setup_id: setup_id, ticker: ticker,
                    account: account_name, broker: broker,
                    side: side, status: status, trade_date: trade_date,
                    atr: atr, atr_factor: atr_factor, scale_in: scale_in, commissions: commissions,
                    initial_stop_loss: initial_stop_loss, init_risk_share: init_risk_share,
                    rps_exit: rps_exit,
                    trade_type: trade_type, setup_src: setup_src, entry_signal: entry_signal,
                    trailing_stop_type: trailing_stop_type, support: support,
                    current_stop: current_stop, current_risk_share: current_risk_share,
                    init_risk_position: init_risk_position,
                    init_risk_share: init_risk_share, escrow: escrow, tgt_gain_pts: tgt_gain_pts,
                    rps_exit: rps_exit,
                    tags: tags}))
    add_tag "setup_src", params.fetch(:setup_src) { "NA" }
    add_tag "entry_signal", params.fetch(:entry_signal) { "NA" }
    add_tag "trade_type", params.fetch(:trade_type) { "NA" }
    add_tag "NH" if @lvc.new_high(sec_id)
    add_tag "mkt_bias", value   if (value=@lvc.mkt_bias)  != "NA"
    add_tag "mkt_energy", value if (value=@lvc.mkt_energy) != "NA"
    add_params_tags(params[:tags])
    debug "=======5 PositionProxy#create_position(#{params[:account_name]},#{pos_id} trailing_stop_type=#{trailing_stop_type}"
    pos_id
  end

  def valid?
    (ticker && ticker.size > 0)
  end

  def info
    persister_name
  end

  def set_status(new_status)
    old_status = status
    self.status = new_status
    pub_update({status: status})
    old_status
  end

  def current_stop
    #puts "Float(@store.getter(#{@pos_id}, \"current_stop\")) rescue nil"
    Float(@store.getter(@pos_id, "current_stop")) rescue nil
  end

  def next_stop_trigger
    Float(@store.getter(@pos_id, "next_stop_trigger")) rescue nil
  end

  def method_missing(methId, *args, &block)
    #puts "PositionProxy#method_missing(#{methId}, #{args}) #{methId.class}"
    case methId.id2name
    when /=/
      #self.class.send(:define_method, methId) do
      #  @store.setter(@pos_id,methId.id2name.chomp("="),args)
      #end
      puts "PositionProxy: @store.setter(#{@pos_id},#{methId.id2name.chomp("=")},#{args})"
      @store.setter(@pos_id,methId.id2name.chomp("="),args)
    when 'current_risk_share', 'init_risk_share', 'setup_support', 'commissions',
         'avg_entry_px', 'last_entry_px', 'quantity', 'position_qty', 'support',
         'mm_entry_px', 'tgt_gain_pts', 'rps_exit',
         'realized', 'unrealized', 'r_multiple', 'r_multiple_unreal',
         'initial_stop_loss', 
         'mark_px', 'avg_exit_px', 'escrow', 'init_risk_position', 'entry_stop_price', 'atr_factor', 'atr'
      self.class.send(:define_method, methId) do
        Float(@store.getter(@pos_id, methId.id2name)).round(2) rescue nil
      end
      #puts "PositionProxy#method_missing: @store.getter(#{@pos_id}, #{methId.id2name}).to_f"
      @store.getter(@pos_id, methId.id2name).to_f
    when 'sidex', 'setup_id', 'sec_id', 'mm_size', "order_qty", "days"
      self.class.send(:define_method, methId) do
        @store.getter(@pos_id, methId.id2name).to_i
      end
      @store.getter(@pos_id, methId.id2name).to_i
    when 'entry_signal', 'broker', 'account_name', 'status', 'side',
         'setup_src', 'adjust_stop_trigger', 'ticker', 'mkt',
         'trailing_stop_type', "closed_date", "trade_date", "trade_type", "tags", "scale_in"
      self.class.send(:define_method, methId) do
        @store.getter(@pos_id, methId.id2name)
      end
      @store.getter(@pos_id, methId.id2name)
    else
      super
    end
  end

  def update_support_level(level)
    debug "PositionProxy#update_support_level(#{level}) support=#{support}  side=#{side}\n"
    current_support = support
    if(side == "long"  && level > (support||1)) || (side == "short" && level < (support||9999))
      self.support = level 
      pub_update({support: level})
    end
    show_action "PositionProxy#update_support_level(#{pos_id}): #{current_support} ==> #{support}"
  end

  def update_atr(level=nil)
    level ||= @lvc.atr(sec_id)
    current_atr = atr || 0.0
    if (level && (current_atr-level).abs > 0.01)
      self.atr = level
      pub_update({atr: atr})
      show_action "PositionProxy#update_atr(#{pos_id}): #{current_atr} ==> #{atr}"
    end
    level
  end

  def update_stop_price(price=nil)
    changed = false
    old_stop = current_stop
    debug "PositionProxy#update_stop_price: 1 pos_id=#{pos_id}  old_stop.to_f=#{old_stop}/#{old_stop.to_f}"
    new_stop = calc_stop_price(price) 
    debug "PositionProxy#update_stop_price: 2 pos_id=#{pos_id}  new_stop=#{new_stop}"
    unless (new_stop.is_a?(Numeric) && new_stop > 0.0)
      raise(InvalidStopLoss.new, "Bad trailing stop loss for pos:#{pos_id}")
    end
    debug "PositionProxy#update_stop_price: 3 pos_id=#{pos_id}  new_stop=#{new_stop}"
    unless (old_stop.is_a?(Numeric) && old_stop > 0.0)
      self.current_stop = old_stop = ((side == "long") ? 0 : 99_999)
      #self.initial_stop_loss = current_stop     #smz
      self.initial_stop_loss = new_stop     #smz
      pub_update({initial_stop_loss: initial_stop_loss})
    end
    delta = (new_stop.to_f - old_stop.to_f) * sidex
    debug "PositionProxy#update_stop_price: 4 pos_id=#{pos_id}  sidex=#{sidex}"
    debug "PositionProxy#update_stop_price: 5 pos_id=#{pos_id}  delta=#{delta}"
    if (delta/old_stop.to_f >= 0.01 || delta > 0.05)
      debug "PositionProxy#update_stop_price: 6 new_stop=#{new_stop}"
      self.current_stop = new_stop
      exit_mgr.save_exit(pos_id, "trailing", current_stop)
      #self.next_stop_trigger = new_stop_trigger
      pub_update({current_stop: current_stop})
      changed = true
      show_action "PositionProxy#update_stop_price(#{pos_id}/#{ticker}): #{old_stop} ==> #{current_stop}"
    end
    changed
  rescue InvalidStopLoss => e
    warn "#{e.class}: <#{e.message}>   from <#{e.backtrace.first}>??"
    changed
  end

  def buy(qty, price, trade_date=DateTimeHelper::integer_date)
    show_action "PositionProxy#buy(#{pos_id}): #{qty} @ #{price}"
    warn "Position(#{@pos_id})Buying quantity, WTF" unless qty > 0
    return quantity unless qty > 0
    price = price.to_f
    #over_fill    = 0
    old_quantity = quantity
    self.quantity = old_quantity + qty
    case self.side
    when 'long'
      set_status('open')
      self.trade_date  = trade_date  # ||= DateTimeHelper::integer_date
      self.position_qty += qty
      puts "self.avg_entry_px  = ((#{old_quantity.abs} * #{avg_entry_px} + #{qty.abs} * #{price}) / #{quantity.abs}).round(3)"
      self.avg_entry_px  = ((old_quantity.abs * avg_entry_px + qty.abs * price) / quantity.abs).round(3)
      self.last_entry_px = price
      update_escrow(-1 * qty * price)
      pub_update(quantity: quantity, position_qty: position_qty, trade_date: trade_date,
                 avg_entry_px: avg_entry_px, last_entry_px: last_entry_px)
    when 'short'
      set_status('unwind')
      if quantity        >= 0 then
        #close_position
        #over_fill        = quantity.abs
        quantity = 0
      end
      update_realized(price,qty)
      update_unrealized(price)
      update_avg_exit_px(price,qty,old_quantity)
      pub_update(quantity: quantity)
    else
      raise "Position#buy:: side(#{side}) Not understood"
    end

    show_info "PositionProxy#buy(#{pos_id}): status            : #{status}"
    show_info "PositionProxy#buy(#{pos_id}): quantity          : #{quantity}"
    show_info "PositionProxy#buy(#{pos_id}): position_qty      : #{position_qty}"
    show_info "PositionProxy#buy(#{pos_id}): avg_entry_px      : #{avg_entry_px}"
    show_info "PositionProxy#buy(#{pos_id}): last_entry_px     : #{last_entry_px}"
    show_info "PositionProxy#buy(#{pos_id}): escrow            : #{escrow}"
    show_info "PositionProxy#buy(#{pos_id}): realized          : #{realized}"
    show_info "PositionProxy#buy(#{pos_id}): unrealized        : #{unrealized}"
    show_info "PositionProxy#buy(#{pos_id}): r_multiple        : #{r_multiple}"
    show_info "PositionProxy#buy(#{pos_id}): r_multiple_unreal : #{r_multiple_unreal}"
    show_info "PositionProxy#buy(#{pos_id}): avg_exit_px       : #{avg_exit_px}"
    
    quantity
  end
  
  def sell(qty, price, trade_date=DateTimeHelper::integer_date)
    show_action "PositionProxy#sell(#{pos_id}): #{qty} @ #{price}"
    warn "Position(#{@pos_id})Selling quantity, WTF" unless qty > 0
    return quantity unless qty > 0
    old_quantity = quantity.to_f
    price = price.to_f
    #over_fill = 0
    self.quantity = quantity - qty
    case side 
    when 'short'
      set_status('open')
      self.position_qty = position_qty - qty
      puts "PositionProxy#sell: self.avg_entry_px = ((#{old_quantity.abs} * #{avg_entry_px} + #{qty.abs} * #{price}) / #{quantity.abs}).round(3)"
      self.avg_entry_px = ((old_quantity.abs * avg_entry_px +
                           qty.abs * price) / quantity.abs).round(3)
      self.last_entry_px = price
      self.trade_date  = trade_date  # ||= DateTimeHelper::integer_date
      pub_update(quantity: quantity, position_qty: position_qty, trade_date: trade_date,
                 avg_entry_px: avg_entry_px, last_entry_px: last_entry_px)
    when 'long'
      set_status('unwind')
      if(quantity <= 0) then
        #close_position
        #over_fill = quantity.abs
        quantity = 0
      end
      update_realized(price,qty)
      update_unrealized(price)
      update_avg_exit_px(price,qty,old_quantity)
      pub_update(quantity: quantity)
    else
      raise "Position#sell:: side(#{side}) Not understood"
    end

    show_info "PositionProxy#sell(#{pos_id}): status            : #{status}"
    show_info "PositionProxy#sell(#{pos_id}): quantity          : #{quantity}"
    show_info "PositionProxy#sell(#{pos_id}): position_qty      : #{position_qty}"
    show_info "PositionProxy#sell(#{pos_id}): avg_entry_px      : #{avg_entry_px}"
    show_info "PositionProxy#sell(#{pos_id}): last_entry_px     : #{last_entry_px}"
    show_info "PositionProxy#sell(#{pos_id}): escrow            : #{escrow}"
    show_info "PositionProxy#sell(#{pos_id}): realized          : #{realized}"
    show_info "PositionProxy#sell(#{pos_id}): unrealized        : #{unrealized}"
    show_info "PositionProxy#sell(#{pos_id}): r_multiple        : #{r_multiple}"
    show_info "PositionProxy#sell(#{pos_id}): r_multiple_unreal : #{r_multiple_unreal}"
    show_info "PositionProxy#sell(#{pos_id}): avg_exit_px       : #{avg_exit_px}"

    quantity
  end
  
  def order_filled
    set_status('filled')
    rtn = [escrow,0].max
    show_action "PositionProxy#order_filled(pos_id: #{pos_id}): status ==> #{status}, remaining escrow ==> #{escrow}"
    update_escrow(-1 * escrow)
    rtn
  end

  def release_escrow
    show_action "release_escrow, escrow=#{escrow}"
    rtn = [escrow,0].max
    update_escrow(-1 * escrow)
    rtn
  rescue
    0
  end

  def update_trailing_stop_type(type)
    debug "PositionProxy#update_trailing_stop_type: #{trailing_stop_type} -> #{type}"
    if TrailingStops.include?(type)
      self.trailing_stop_type = type
      pub_update({trailing_stop_type: type})
    else
      warn "Trailing stop type: #{type} NOT known for position #{pos_id}"
    end
    debug "PositionProxy#update_trailing_stop_type: then #{trailing_stop_type} -> #{type}"
  end

  def update_atr_factor(factor)
    debug "PositionProxy#update_atr_factor: #{atr_factor} -> #{factor}"
    #if factor.is_a?(Numeric) && factor.to_f > 0.0 && factor.to_f <= 3.0
    if MiscHelper::is_number?(factor) && factor.to_f > 0.0 && factor.to_f <= 3.0
      self.atr_factor = factor
      pub_update({atr_factor: factor})
    else
      warn "ATR factor: #{factor} NOT numeric or out of range #{pos_id}"
    end
    debug "PositionProxy#update_atr_factor: then #{atr_factor} -> #{factor}"
  end

  def close_position(close_tag=false)
    show_action "close_position"
    update_days_in
    set_status('closed')
    self.closed_date = DateTimeHelper::integer_date
    show_info "PositionProxy#close_position self.realized    = (#{position_qty} * (#{avg_exit_px} - #{avg_entry_px}) * #{sidex}).round(2)"
    remove_position_alerts(pos_id)
    add_tag "closed", close_tag if close_tag
    pub_update(closed_date: closed_date, days: days)
  end
  
  def stop_action
    (side == 'long') ? :sell : :buy
  end
  
# 20150302
=begin 
  def unwind_order
   OrderProxy.new( {pos_id:       @pos_id,
                    sec_id:       sec_id,
                    ticker:       ticker,
                    mkt:          mkt,
                    action:       stop_action,
                    action2:      :to_close,
                    order_qty:    quantity.abs,
                    leaves:       quantity.abs,
                    filled_qty:   0.0,
                    price_type:   'MKT',
                    limit_price:  0,
                    broker:       broker}, @order_store )
  end
=end

  def to_human
    "pos(#{pos_id}) #{quantity} #{ticker}(#{sec_id}) to #{broker} #{status}"
  end

  def db_parms
    { pos_id:                  @pos_id,
      sec_id:                  sec_id,
      setup_id:                setup_id,
      side:                    side,
      quantity:                0,  #quantity,
      position_qty:            0,  #position_qty,
      status:                  status,
      closed_date:             closed_date,
      trade_date:              trade_date,
      account:                 account_name,
      setup_src:               setup_src,
      trade_type:              trade_type,
      entry_signal:            entry_signal,
      broker:                  broker,
      init_risk_share:         init_risk_share,
      init_risk_position:      init_risk_position,
      rps_exit:                rps_exit,
      avg_entry_px:            0,  #avg_entry_px,
      last_entry_px:           last_entry_px,
      realized:                0,  #realized,
      unrealized:              0,  #unrealized,
      r_multiple:              0,
      r_multiple_unreal:       0,
      avg_exit_px:             0,   #avg_exit_px,
      commissions:             0,   #commissions,
      tags:                    tags
    }
  end
  
  def add_commissions(amount)
    comm = @store.add_commissions(@pos_id, amount)
    pub_update({commissions: comm})
  end

  def mark(price)
    debug "mark pos #{pos_id} at #{price}"
    #@store.setter(@pos_id, :mark_px, price)
    self.mark_px = price
    update_days_in
    pub_update({mark_px: price, days: days})
    update_unrealized(price)
  end

  def add_tag(name,value=nil)
    puts "add_tag(#{name},#{value})"
    #db_queue.push(DbDataQueue::Message.new(command: "position_tag", data: {pos_id: pos_id, tags: name, value: value}))
    self.tags   =  tags + "," if tags
    self.tags ||= ""
    tag_str = (value ? "#{name}:#{value}" : name)
    self.tags  += tag_str
    db_queue.push(DbDataQueue::Message.new(command: "position_tag", data: {pos_id: pos_id, tags: tag_str}))
  end

  def dump
    @store.dump(@pos_id)
  end

  ############
  private
  ############

  def persister_name
    @store.whoami
  end

  def pub_update(data)
    debug "pub_update(#{data})"
    command = "update_position"
    payload = data.merge(pos_id: pos_id)
    debug "pub_update: db_queue.push(DbDataQueue::Message.new(command: #{command}, data: #{payload}))"
    db_queue.push(DbDataQueue::Message.new(command: command, data: payload))
  end

  def add_params_tags(ptags)
    puts "add_params_tags(#{ptags})"
    return unless ptags
    #tags="charts,bop:11,trend_dir:+,bop_rank:0.5,bop_5d_rank:1.0,rsi_signal1,rsi_signal2,volsig1,bopsig1"
    ptags.split(";").each do |tag|
      name,value = tag.split(":")
    puts "add_params_tags: name=#{name}  value=#{value}"
      next unless name
      add_tag(name,value)
    end
  end

  def update_days_in
    self.days = DateTimeHelper::days(trade_date,DateTimeHelper::integer_date) unless is_closed?
  end

  def remove_position_alerts(pos_id)
    warn "NEED SOME CODE HERE"
  end
 
  def set_position_defaults(params)
    debug "set_position_defaults: side=#{params[:side]} support=#{params[:support]}  setup_support=#{params[:setup_support]}\n"
    params[:current_risk_share] ||= params[:init_risk_share]
    params[:sidex]             ||= (params[:side]=="long" ? 1 : -1)
    params[:setup_support]     ||= (params[:side]=="long" ? 0 : 99999)
    debug "set_position_defaults: setup_support=#{params[:setup_support]}\n"
    params[:support]           ||= (params[:setup_support].is_a?(Numeric) ? params[:setup_support]
                                                                        : (params[:side]=="long" ? 0 : 99999))
    debug "set_position_defaults: support=#{params[:support]}\n"
    params[:commissions]       ||= 0
    params[:quantity]          ||= 0
    params[:position_qty]      ||= 0
    params[:avg_entry_px]      ||= 0
    params[:last_entry_px]     ||= 0
    params[:avg_exit_px]       ||= 0
    params[:atr_factor]        ||= 0
    params[:atr]               ||= 0
    params[:mark_px]           ||= params[:avg_entry_px] || nil
    params[:realized]          ||= 0
    params[:unrealized]        ||= 0
    params[:r_multiple]        ||= 0
    params[:r_multiple_unreal] ||= 0
    params[:escrow]            ||= 0
    params[:rps_exit]          ||= 0
    params[:status]            ||= 'init'
    params[:initial_stop_loss] ||= nil
    params[:closed_date]       ||= nil
    params[:scale_in]          ||= nil
  end

  def calc_stop_price(price)
    show_info "PositionProxy#calc_stop_price(#{pos_id})(#{price})"
    debug "PositionProxy#calc_stop_price trailing_stop_type=#{trailing_stop_type}"

    return current_stop if trailing_stop_type == "timed"

    new_stop = exit_mgr.send(trailing_stop_type, self, price.to_f)
    new_stop
  end

  def update_unrealized(price)
    debug "self.unrealized = (#{quantity.abs} * (#{price} - #{avg_entry_px}) * #{sidex}).round(3)"
    self.unrealized = (quantity.abs * (price - avg_entry_px) * sidex).round(3)
    debug "unrealized=#{unrealized}"
    debug "self.r_multiple_unreal = (#{unrealized} / #{init_risk_position}).round(2)"
    self.r_multiple_unreal = (unrealized / init_risk_position).round(2)
    debug "r_multiple_unreal=#{r_multiple_unreal}"
    debug "pub_update({unrealized: #{unrealized}, r_multiple_unreal: #{r_multiple_unreal}})"
    pub_update({unrealized: unrealized, r_multiple_unreal: r_multiple_unreal})
  rescue
    warn "Error updating unrealized for pos: #{pos_id}"
  end

  def update_realized(price,qty)
    show_info "self.realized = (#{realized} + #{qty.to_f} * (#{price} - #{avg_entry_px}) * #{sidex}).round(2)"
    self.realized = (realized + qty.to_f * (price - avg_entry_px) * sidex).round(2)
    self.r_multiple = (realized / init_risk_position).round(2)
    pub_update({realized: realized, r_multiple: r_multiple})
  rescue
    warn "Error updating realized for pos: #{pos_id}"
  end

  def update_avg_exit_px(price,qty,old_quantity)
    puts "PositionProxy#update_avg_exit_px/#{pos_id}: avg_exit_px = ((#{avg_exit_px} * (#{position_qty.abs} - #{old_quantity}.abs) + #{price} * #{qty}) / (#{position_qty}.abs - #{old_quantity}.abs + #{qty})).round(3)"
    self.avg_exit_px = ((avg_exit_px * (position_qty.abs - old_quantity.abs)      \
                         + price * qty) /                                         \
                         (position_qty.abs - old_quantity.abs + qty)).round(3)
    pub_update({avg_exit_px: avg_exit_px})
  rescue
    warn "Error updating avg_exit_px for pos: #{pos_id}"
  end

  def update_escrow(amount)
    self.escrow       += amount
    pub_update({escrow: escrow})
  end
end

