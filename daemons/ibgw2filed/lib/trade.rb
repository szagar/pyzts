class Trade
  attr_accessor :ticker
  attr_accessor :atr_factor
  attr_accessor :broker
  attr_accessor :broker_account
  attr_accessor :init_risk_position
  attr_accessor :init_risk_share
  attr_accessor :work_price
  attr_accessor :mm_size
  attr_accessor :entry_signal
  attr_accessor :support
  attr_accessor :trade_type
  attr_accessor :side
  attr_accessor :entry_stop_price
  attr_accessor :trailing_stop_type
  attr_accessor :rps_exit
  attr_accessor :time_exit
  attr_accessor :tgt_gain_pts
  attr_accessor :limit_price
  attr_accessor :sec_id
  attr_accessor :pos_id
  attr_accessor :setup_id
  attr_accessor :mkt
  attr_accessor :setup_src
  attr_accessor :escrow
  attr_accessor :tags, :notes

  def initialize(account_name, entry_id)
    @account_name = account_name
    @entry_id     = entry_id
  end

  def account_name
    @account_name
  end

  def within_capital_limit?(capital_next_trade)
    #puts "within_capital_limit?(#{capital_next_trade})"
    #puts "(#{mm_size} * #{limit_price}) <= #{capital_next_trade}"
    (mm_size * limit_price) <= capital_next_trade
  end

  def size_to_withing_capital(capital_next_trade)
    [mm_size, (capital_next_trade/limit_price).round(0)].minimum
  rescue
    0.0
  end

  def attributes
    { account_name:       @account_name,
      entry_id:           @entry_id,
      ticker:             ticker,
      atr_factor:         atr_factor,
      broker:             broker,
      broker_account:     broker_account,
      sec_id:             sec_id,
      pos_id:             pos_id,
      setup_id:           setup_id,
      setup_src:          setup_src,
      mkt:                "stock",
      init_risk_position: init_risk_position,
      init_risk_share:    init_risk_share,
      escrow:             escrow,
      work_price:         work_price,
      mm_size:            mm_size,
      entry_signal:       entry_signal,
      trade_type:         trade_type,
      side:               side,
      entry_stop_price:   entry_stop_price,
      trailing_stop_type: trailing_stop_type,
      rps_exit:           rps_exit,
      time_exit:          time_exit,
      support:            support,
      tgt_gain_pts:       tgt_gain_pts,
      limit_price:        limit_price,
      tags:               tags,
      notes:              notes,
    }
  end

  def humanize
    attributes
  end

  def add_note(str)
    @notes = ((@notes && @notes!="") ? @notes+"; " : "")
    @notes += str
  end

  #####################
  private
  #####################

end
