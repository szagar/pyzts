PositionStruct = Struct.new( 
                          :pos_id,
                          :setup_id          ,
                          :entry_id          ,
                          :ticker            ,
                          :sec_id            ,
                          :mkt               ,
                          :side              ,
                          :setup_src         ,
                          :trade_type        ,
                          :entry_name        ,
                          :broker            ,
                          :init_risk         ,
                          :current_risk_share,              #
                          :order_qty         ,
                                             
                          :mm_size           ,
                          :mm_entry_px       ,
                                             
                          :account           ,
                          :quantity          ,              #
                          :position_qty      ,              #
                          :avg_entry_px      ,              #
                          :avg_exit_px       ,              #
                          :commissions       ,              #
                          :setup_support     ,              #
                          :support           ,              #
                          :trailing_stop_type,              #
                          :support           ,              #
                          :adjust_stop_trigger,              #
                          :current_stop      ,              #
                          :next_stop_trigger ,              #
                          :realized          ,              #
                          :unrealized        ,              #
                          :status            ,
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
  
  def <=>(other)
    self[:ticker] <=> other[:ticker]
  end
  
  def to_human
  end

  def to_human_1
  end

  def to_human_2
  end
end

