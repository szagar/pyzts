class NullOrder
  def valid?
    false
  end
end

OrderStruct = Struct.new( :order_id,
                          :setup_id,
                          :entry_id,
                          :sec_id,
                          :perm_id,
                          :pos_id,

                          :action,
                          :action2,
                          :mkt,
                          :setup_src,
                          :trade_type,
                          :ticker,
                          :order_qty,
                          :tif,
                          :leaves,
                          :filled_qty,
                          :avg_price,
                          :order_status,
                          :price_type,
                          :limit_price,
                          :stop_price,
                          :notes,

                          :side,

                          :account_name,
                          :broker_account,
                          :broker,
                          :broker_ref,
                      ) do
  def self.from_hash(attributes)
    instance = self.new
    attributes.each do |key, value|
      next unless self.members.include?(key.to_sym)
      instance[key] = value
    end
    instance
  end
  
  def add_note(str)
    @notes = ((@notes && @notes!="") ? @notes+"; " : "")
    @notes += str
  end

  def attributes
    result = {}
    members.each do |name|
      result[name] = self[name]
    end
    result
  end
  
  def valid?; debug "Order#valid? Need some code"; true; end

  def to_human
    "#{account_name}/#{perm_id}/#{pos_id}: #{action} #{filled_qty}/#{order_qty} #{ticker} @ #{limit_price} #{order_status}"
  end
  
  def db_parms
    { perm_id: perm_id, pos_id: pos_id, sec_id: sec_id, ticker: ticker, status: order_status,
      action: action, action2: action2, limit_price: limit_price, price_type: price_type, 
      avg_price: avg_price, order_qty: order_qty, filled_qty: filled_qty, leaves: leaves,
      broker: broker, broker_account: broker_account, 
      account_name: account_name, tif: tif, broker_ref: broker_ref, notes: notes }
  end
end


