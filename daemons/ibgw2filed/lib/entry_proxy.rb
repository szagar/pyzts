$: << "#{ENV['ZTS_HOME']}/etc"
require "store_mixin"
require "date_time_helper"
#require "redis_store"
require "zts_constants"
require "log_helper"

class EntryStore 
  include Store
  include LogHelper
  def initialize
    show_info "EntryStore#initialize"
    super
  end
  def expire_at_next_close(id)
    redis.expire pk(id), DateTimeHelper::secs_until_next_close
  end
end

class  EntryProxy
  include LogHelper

  def initialize(params, persister=EntryStore.new)
    show_info "EntryProxy#initialize"
    @persister = persister
    @entry_id = params.fetch(:entry_id) { create_entry(params) }
  end
  
  def entry_id
    @entry_id
  end

  def create_entry(params)
    puts "smz EntryProxy#create_entry: params=#{params}"
    set_defaults(params)
    puts "EntryProxy#create_entry: params=#{params}"
    params[:sidex] = ((params[:side] == "long") ? 1 : -1)
    id = @persister.create(params)
    id
  end

  def clone(params)
    puts "EntryProxy#clone: params=#{params}"
    id = @persister.create(params)
    id
  end

  def expire_at_next_close
    @persister.expire_at_next_close(entry_id)
  end

  def valid?
    #(ticker && ticker.size > 0)
    puts "EntryProxy#valid?"

    rtn = true
    puts "EntryProxy#valid?  check side"
    unless %w(long short).include?(side)
      warn "entry:#{entry_id} unknown side:#{side}"
      rtn = false
    end
    puts "EntryProxy#valid?  check entry_signal"
    puts "entry_signal=#{entry_signal}"
    puts "ZtsConstants::LongEntrySignals=#{entry_signal}"
    unless ZtsConstants::LongEntrySignals.include?(entry_signal)
      warn "entry:#{entry_id} unknown entry_signal:#{entry_signal}"
      rtn = false
    end
    puts "EntryProxy#valid?  check work_price"
    unless work_price.is_a?(Numeric)
      warn "entry:#{entry_id} Invalid work_price:#{work_price}"
      rtn = false
    end
    puts "EntryProxy#valid?  check limit_price"
    unless limit_price.is_a?(Numeric)
      warn "entry:#{entry_id} Invalid limit_price:#{limit_price}"
      rtn = false
    end
    puts "EntryProxy#valid?  return = #{rtn}"
    rtn
  rescue
    warn "invalid entry!, entry:#{dump}"
    false
  end

  def info
    persister_name
  end

  def attributes(fields=members)
    debug "EntryProxy#attributes(#{fields})"
    result = {}
    fields.each do |name|
      result[name] = self.send name
    end
    result
  end

  def dump
    @persister.dump(@entry_id)
  end

  def humanize
    "#{setup_src}/#{ticker}/#{trade_type}/#{broker}"
  end

  def set_status(new_status)
    old_status = status
    self.status = new_status
    old_status
  end

  def method_missing(methId, *args, &block)
    #puts "Order#method_missing(#{methId}, #{args}) #{methId.class}"
    case methId.id2name
    when /=/
      @persister.setter(@entry_id,methId.id2name.chomp("="),args)
    when 'order_qty', 'leaves', 'filled_qty', 'avg_price', 'entry_stop_price',
      'stop_loss_price', 'sidex', 'est_risk_share', 'est_stop_loss',
      'weak_support', 'moderate_support', 'strong_support', 'avg_run_pt_gain',
      'tgt_gain_pts', 'swing_rr', 'position_rr', 'adjust_stop_trigger',
      'daytrade_exit', 'rps_exit', 'setup_support', 'support', 'limit_price', 'work_price', 'atr'
      self.class.send(:define_method, methId) do
        Float(@persister.getter(@entry_id, methId.id2name)).round(2) rescue nil
      end
      Float(@persister.getter(@entry_id, methId.id2name)).round(2) rescue nil
    when 'pos_id', 'setup_id', 'sec_id', 'mm_size',
      'triggered_entries', 'pending_entries'
      self.class.send(:define_method, methId) do
        @persister.getter(@entry_id, methId.id2name).to_i
      end
      @persister.getter(@entry_id, methId.id2name).to_i
    when 'action', 'action2', 'ticker', 'status', 'price_type', 'tif',
         'broker', 'mkt', 'entry_signal', 'entry_filter', 'side', 'setup_src', 'trade_type',
         'tod', 'trailing_stop_type', 'tags', 'notes', 'pyramid_pos', 'mca', 'mca_tkr'
      self.class.send(:define_method, methId) do
        @persister.getter(@entry_id, methId.id2name)
      end
      @persister.getter(@entry_id, methId.id2name)
    else
      super
    end
    #@persister.send(methId, @account)
  end

  def pyramid?
    pyramid_pos == "true"
  end

  private

  def persister_name
    @persister.whoami
  end

  def set_defaults(params)
    params[:pyramid_pos] ||= false
  end

  def members
    puts "EntryProxy#members"
    m = @persister.members(@entry_id)
    puts "EntryProxy#members: m=#{m}"
    m
  end
end

