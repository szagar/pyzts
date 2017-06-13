def stop_loss(entry)
  case entry.trade_type
  when "support"
       entry.support - sidex * ((entry.work_price < 10.0) ? 0.12 : 0.25)
  when "atr"
  when "ema"
       exit_
  else
  end
end

def support(entry)
  case entry.trade_type
  when "Swing"
    entry.support = MiscHelper::first_numeric(entry.support, entry.weak_support)
  when "Position"
    entry.support = MiscHelper::first_numeric(entry.support, entry.moderate_support)
  else
    raise InvalidSetupError.new, "trade_type: #{entry.trade_type} Not known"
    #entry.support = MiscHelper::first_numeric(entry.support, entry.weak_support,
    #                                          entry.moderate_support, entry.strong_support)
  end

  raise InvalidSetupError.new("missing support") unless valid_price?(entry.support)
  sidex         = get_sidex(entry.side)
  entry.stop_loss_price = entry.support -
                          sidex * ((entry.work_price < 10.0) ? 0.12 : 0.25)
end

def atr(entry)
  raise InvalidSetupError, "ATR not available" unless valid_atr?(entry.sec_id)
end

def ema(entry)
  level = (entry.side == "long") ? "low" : "high"
  ema = lvc.ema(entry.sec_id,level,34)
  raise InvalidSetupError, "EMA not availablefor sec_id:#{entry.sec_id}" unless valid_price?(ema)
  entry.support         =  ema
  entry.stop_loss_price =  entry.support
end

def tightest(entry)
end
