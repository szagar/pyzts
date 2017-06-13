module ZtsConstants

  MIN_RTN_RISK = 2.5
  MIN_TGT_PT_GAIN = 1
  #MIN_TGT_PT_GAIN = 10
  MIN_RUN_PTS = 3

  #INITIAL_MARGIN     = 0.25
  #MAINTENANCE_MARGIN = 0.25
  INITIAL_MARGIN     = 0.50
  MAINTENANCE_MARGIN = 1.0

  TrailingStops    = %w(atr support support_x manual ema tightest timed)
  LongEntrySignals = %w(engulfing-white dragon pre-buy descretionary springboard systematic wave)
  TradeType        = %W(DayTrade Swing Position Velocity LongTerm Trend)

  OrderStatus      = {Submitted: "10", Filled: "20", Cancelled: "30", Submitted: "40", PendingSubmit: "50", PreSubmitted: "60", PendingCancel: "70"}
  OrderStatusHuman = OrderStatus.invert

  PosStatus      = {init: "10", pending: "20", open: "30", unwind: "40", closed: "50", cancel: "60"}
  PosStatusHuman = PosStatus.invert

  EntryPending    = 0
  EntryOpen       = 1
  EntryTriggered  = 2
  
  EntryStatus={ EntryPending   => :EntryPending,
                EntryOpen      => :EntryOpen,
                EntryTriggered => :EntryTriggered }
  
  TkrDivisor = 100000
  Markets = {stock: 1, index: 2}    # add any new markers to end of array
  MarketsIndex = Markets.invert
end

