OrderStruct = Struct.new( :order_id,                                   # new
                          :action2,     :order_qty,  :price_type,      # new
                          :tif,                                        # new
                          :leaves,      :filled_qty,  :avg_price,      # new
                          :notes,                                      # new

                          :limit_price,                                # modified

                          :setup_id,    :ticker,      :sec_id,   :mkt, # pass thru
                          :setup_src,   :trade_type,  :side,           # pass thru
                          :entry_id,    :entry_name,
                          :account,     :broker_acct,                  # pass thru
                          :perm_id,     :pos_id,                       # pass thru
                          :order_status,:action,                       # pass thru
                          :size,                                       # pass thru
                          :broker,      :broker_ref,                   # pass thru
                          :stop_price,                                 # pass thru


                      ) do
  def self.from_hash(attributes)
    instance = self.new
    attributes.each do |key, value|
      next unless self.members.include?(key.to_sym)
      instance[key] = value
    end
    instance
  end
  
  def attributes
    result = {}
    members.each do |name|
      result[name] = self[name]
    end
    result
  end
  
  def to_human
    "#{account}/#{perm_id}/#{pos_id}: #{action} #{filled_qty}/#{order_qty} #{ticker} @ #{limit_price} #{order_status}"
  end
  
  def db_parms
    { perm_id: perm_id, pos_id: pos_id, sec_id: sec_id, ticker: ticker, status: order_status,
      action: action, action2: action2, limit_price: limit_price, price_type: price_type, 
      avg_price: avg_price, order_qty: order_qty, filled_qty: filled_qty, leaves: leaves, broker: broker, 
      account: account, tif: tif, broker_ref: broker_ref, notes: notes }
  end
end


