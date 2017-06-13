AccountStruct = Struct.new( 
                          :name              ,
                          :account_id        ,
                          :money_mgr         ,
                          :position_percent  ,
                          :cash              ,
                          :net_deposits      ,
                          :core_equity       ,
                          :equity_value      ,
                          :locked_amount     ,
                          :available_funds   ,
                          :atr_factor        ,
                          :min_shares        ,
                          :lot_size          ,
                          :equity_model      ,
                          :broker            ,
                          :broker_AccountCode,
                          :no_trades         ,
                          :no_trades_today   ,
                          :no_open_positions ,
                          :risk_dollars      ,
                          :reliability       ,
                          :expectancy        ,
                          :sharpe_ratio      ,
                          :vantharp_ratio    ,
                          :realized          ,
                          :unrealized        ,
                          :maxRp             ,
                          :maxRm             ,
                          :date_first_trade  ,
                          :date_last_trade   ,
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
    self[:name] <=> other[:name]
  end
  
  def to_human
  end

  def to_human_1
  end

  def to_human_2
  end
end

