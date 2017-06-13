FillStruct = Struct.new( :ref_id,        :pos_id,      :sec_id,

                         # IB execution data
                         :local_id,      :exec_id,     :time,
                         :account_name,  :exchange,    :side,
                         :quantity,      :price,       :perm_id,
                         :client_id,     :liquidation, :cumulative_quantity,
                         :average_price, :order_ref,   :ev_rule,
                         :ev_multiplier,

                         # IB contract data
                         :con_id,        :symbol,      :sec_type,
                         :expiry,        :strike,      :right,
                         :multiplier,    :exchange,    :currency,
                         :local_symbol,
                         
                         # additional
                         :broker,        :action,
                         :avg_price,     :commission,
                        ) do
  def self.from_hash(attributes)
    instance = self.new
    attributes.each do |key, value|
      next unless self.members.include?(key.to_sym)
      instance[key] = value
    end
    instance
  end

  def attributes(fields=members)
    result = {}
    fields.each do |name|
      result[name] = self[name]
    end
    result
  end
  
  def to_human
    "Fill(#{exec_id}): #{account_name}/#{sec_id} #{side}:#{action} #{quantity}/#{cumulative_quantity} @#{price}"
  end

end
