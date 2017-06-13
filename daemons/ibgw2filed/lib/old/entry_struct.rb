EntryStruct = Struct.new(
                    :setup_id,        :ticker,          :sec_id,    :mkt,    # pass thru
                    :setup_src,       :trade_type,      :side,  :sidex,      :tod,    # pass thru
                    :entry_stop_price,      :mm_stop_loss,    :stop_loss,          # pass thru
                    :weak_support,    :moderate_support,  :strong_support,   # pass thru
                #   :avg_run_pt_gain, :tgt_gain_pts,                         # pass thru
                #   :swing_rr,        :position_rr,                          # pass thru
                    :adjust_stop_trigger,                                    # pass thru
                    :day_trade_exit,                                         # pass thru
                    :setup_support,     :support,                            # pass thru
                    :limit_price,                                            # pass thru
                    :est_risk_share,  :est_stop_loss,

                    :entry_id,        :entry_name,      :entry_status,       # new
                    :entry_type,      :action,                               # new

                    :pos_id,
                    :atr,         :atr_factor,
                    :init_risk,
                    :size,        :equity_model,    :risk_dollars,
                    :account,     :dollar_pos,      :broker,
                          
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
    "#{entry_id}/#{setup_id} #{setup_src}/#{trade_type} #{ticker}/#{sec_id}" \
    " #{side} #{entry_name}/#{entry_id} #{stop_price}/#{limit_price}"
  end
end
