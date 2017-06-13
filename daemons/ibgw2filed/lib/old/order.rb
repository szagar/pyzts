class Order
  attr_accessor :perm_id, :pos_id, :account, :broker_acct, :ticker, :sec_id, :broker_ref, :mkt, :action
  attr_accessor :action2, :order_qty, :filled_qty, :leaves, :broker, :avg_price, :limit_price, :price_type
  attr_accessor :tif, :status, :notes

  def initialize(args)
    puts "Order#initialize(#{args})"
    @perm_id    = args[:perm_id]      || 0
    @pos_id     = args[:pos_id]
    @account    = args[:account]      || ""
    @broker_acct= args[:broker_acct]  || ""
    @ticker     = args[:ticker]       || ""
    @sec_id     = args[:sec_id]       || 0
    @broker_ref = args[:broker_ref]   || ""
    @mkt        = args[:mkt]          || ""
    @action     = args[:action]
    @action2    = args[:action2]
    @order_qty  = args[:order_qty]    || 0
    @filled_qty = args[:filled_qty]   || 0
    @leaves     = args[:leaves]       || 0
    @broker     = args[:broker]
    @price_type   = args[:price_type]
    @limit_price  = args[:limit_price]
    @avg_price    = args[:avg_price]
    @tif          = args[:tif]          || ""
    @status       = args[:status]
    @notes        = args[:notes]
  end
  
#  def to_s
#    "pos(#{pos_id}) (#{action}:#{action2}) (#{order_qty}/#{filled_qty}) #{ticker}(#{mkt}:#{sec_id}) @(#{price_type} #{limit_price}) ->(#{broker})"
#  end
  
  def detail
    puts "perm_id       = #{perm_id}"
    puts "pos_id        = #{pos_id}"
    puts "account       = #{account}"
    puts "broker_acct   = #{broker_acct}"
    puts "ticker        = #{ticker}"
    puts "sec_id        = #{sec_id}"
    puts "mkt           = #{mkt}"
    puts "action        = #{action}"
    puts "action2       = #{action2}"
    puts "order_qty     = #{order_qty}"
    puts "filled_qty    = #{filled_qty}"
    puts "leaves        = #{leaves}"
    puts "broker        = #{broker}(#{broker_ref})"
    puts "price_type    = #{price_type}"
    puts "limit_price   = #{limit_price}"
    puts "avg_price   = #{avg_price}"
    puts "tif           = #{tif}"
    puts "status        = #{status}"
  end

  def db_parms
    { perm_id: perm_id, pos_id: pos_id, sec_id: sec_id, ticker: ticker, status: status,
      action: action, action2: action2, limit_price: limit_price, price_type: price_type, 
      avg_price: avg_price, order_qty: order_qty, filled_qty: filled_qty, leaves: leaves, broker: broker, 
      account: account, tif: tif, broker_ref: broker_ref, notes: notes }
  end
  
  def to_human
    "#{account}/#{perm_id}/#{pos_id}: #{action} #{filled_qty}/#{order_qty} @ #{limit_price} #{status}"
  end
end
