class Fill
  attr_accessor :ref_id, :pos_id, :sec_id, :exec_id, :price, :qty
  attr_accessor :broker, :action, :action2, :account, :avg_price, :commission
  def initialize(args)
    @pos_id  = args[:pos_id]
    @sec_id  = args[:sec_id]
    @exec_id  = args[:exec_id]
    @price   = args[:price]
    @avg_price = args[:avg_price]
    @qty     = args[:qty]
    @action  = args[:action]
    @action2 = args[:action2]
    @broker  = args[:broker]
    @account = args[:account]
    @ref_id  = args[:ref_id] || ""
    @ref_id  = args[:commission] || 0
  end
  
  def db_parms
    {ref_id: ref_id, pos_id: pos_id, sec_id: sec_id, exec_id: exec_id, price: price, avg_price: avg_price, quantity: qty, action: action, 
      action2: action2, broker: broker, account: account, commission: commission}
  end
end
