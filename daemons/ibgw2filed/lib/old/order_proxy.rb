$: << "#{ENV['ZTS_HOME']}/etc"

require 'order_store'
require 'store_mixin'

class  OrderProxy
  
  def initialize(params, persister=OrderStore.new)
    @persister = persister
    @order_id = create_order(params)
  end
  
  def order_id
    @order_id
  end

  def create_order(params)
    set_defaults(params)
    @persister.create(params)
  end

  def valid?
    (ticker && ticker.size > 0)
  end

  def info
    persister_name
  end

  def dump
    @persister.dump(@order_id)
  end

  def method_missing(methId, *args, &block)
    #puts "Order#method_missing(#{methId}, #{args}) #{methId.class}"
    case methId.id2name
    when /=/
      #self.class.send(:define_method, methId) do
      #  @persister.setter(@order_id,methId.id2name.chomp("="),args)
      #end
      @persister.setter(@order_id,methId.id2name.chomp("="),args)
    when 'order_qty', 'leaves', 'filled_qty', 'limit_price', 'avg_price'
      self.class.send(:define_method, methId) do
        Float(@persister.getter(@order_id, methId.id2name)).round(2) rescue nil
      end
      Float(@persister.getter(@order_id, methId.id2name)).round(2) rescue nil
    when 'pos_id', 'setup_id', 'sec_id', 'mm_size'
      self.class.send(:define_method, methId) do
        @persister.getter(@order_id, methId.id2name).to_i
      end
      @persister.getter(@order_id, methId.id2name).to_i
    when 'action', 'action2', 'ticker', 'status', 'price_type', 'tif',
         'broker', 'mkt'
      self.class.send(:define_method, methId) do
        @persister.getter(@order_id, methId.id2name)
      end
      @persister.getter(@order_id, methId.id2name)
    else
      super
    end
    #@persister.send(methId, @account)
  end

  private

  def persister_name
    @persister.whoami
  end

  def set_defaults(params)
    params[:tif]             ||= 'Day'
    params[:status]          ||= 'init'
  end

end

