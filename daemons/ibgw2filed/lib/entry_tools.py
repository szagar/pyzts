import talib
from talib.abstract import *
import numpy as np
import secmaster_tools as st
import watchlist_tools as wt
import patterns_tools as pt
import pricestats_tools as pxt

MIN_SHORT_PRICE = 50.00

def short_entry_stop_price(prices):
  work_price = prices['low'][-1]
  if work_price < MIN_SHORT_PRICE:
    raise ValueError("Stock price below min({px}) for short".format(px=repr(MIN_SHORT_PRICE)))
  px_adj = 0.25
  return round(work_price-px_adj,2)

def long_entry_stop_price(prices):
  work_price = prices['high'][-1]
  px_adj = (0.25 if (work_price >= 10) else 0.125)
  if work_price < 5.0: px_adj = 0.06
  return round(work_price+px_adj,2)

def short_limit_price_from_stop(stop_price):
  px_adj = 0.38
  return round(stop_price-px_adj,2)

def long_limit_price_from_stop(stop_price):
  px_adj = (0.38 if (stop_price >= 10) else 0.25)
  if stop_price < 5.0: px_adj = 0.12
  return round(stop_price+px_adj,2)


def set_some_defaults(h):
  h['setup_id'] = None
  #h['pos_id'] = None
  h['tod'] = None
  h['tif'] = None
  h['weak_support'] = None
  h['moderate_support'] = None
  h['strong_support'] = None
  h['setup_support'] = None
  h['avg_run_pt_gain'] = None
  h['swing_rr'] = None
  h['position_rr'] = None
  h['adjust_stop_trigger'] = None
  h['day_trade_exit'] = None
  h['triggered_entries'] = None
  h['pending_entries'] = None
  h['mca_tkr'] = None
  h['mca'] = None

def add_tag(tags,name,value=None):
  t = ""
  if tags and not tags.endswith(";"): t += ";"
  if value is None:
    t += name
  else:
    t += name+":"+str(value)
  return t

def set_tags(ticker,prices):
  print "number of prices = {0}\n".format(len(prices))
  tags = ""
  if len(prices) > 10: 
    for key, value in pt.candle_stick_patterns(prices).iteritems():
       tags += add_tag(tags,key,value)

    for key, value in pxt.price_stats(prices).iteritems():
       tags += add_tag(tags,key,value)

  # add membership tag
  mship = wt.watchlist_membership(ticker)
  if len(mship) > 0:
    tags += add_tag(tags,'membership', ','.join([str(x) for x in mship]))

  return tags


#def gen_entry(side,ticker,entry_filter,setup_src,prices,setup={}):
def gen_entry(setup,prices):
  #print "gen_entry(%s,%s,%s,%s,prices)" % (side,ticker,entry_filter,setup_src)
  print "gen_entry({setup},prices)".format(setup=setup)

  
  print prices
  #setup = {}
  set_some_defaults(setup)
  setup['pos_id'] = setup.get('pos_id',None)
  setup['status'] = "valid"
  print "high: {0}".format(np.asarray(prices['high']))
  print "low: {0}".format(np.asarray(prices['low']))
  print "close: {0}".format(np.asarray(prices['close']))
  setup['atr'] = round(talib.ATR(np.asarray(prices['high']),np.asarray(prices['low']),
                           np.asarray(prices['close']),14)[-1],2)
  print "if {0} == AVXL and {1} == nan : setup['atr'] = 1.11".format(setup['ticker'],setup['atr'])
  if setup['ticker'] == "AVXL" and setup['atr'] != setup['atr'] : setup['atr'] = 1.11
  print "atr: {0}".format(setup['atr'])
  setup['sec_id']      = st.lookup_sid_id(setup['ticker'])
  #setup['ticker']      = ticker
  setup['ticker']      = setup['ticker']
  setup['trade_type']  = "Trend"   # "Position"
  setup['mkt']         = "stock"
  #setup['side']        = side
  setup['side']        = setup['side']
  #setup['setup_src']   = setup_src
  setup['setup_src']   = setup['setup_src']
  if setup['side'] == "short":
    setup['trailing_stop_type']  = setup.get('trailing_stop_type','atr')
    setup['support']  = setup.get('support',round(prices['high'][-1],2)+1.00)    # round(MAX(prices,5)[-1],2))
    try:
      setup['entry_stop_price'] = setup.get('entry_stop_price',None) or short_entry_stop_price(prices)
    except ValueError, msg:
      print "WARN!!!!:"+str(msg)+" ticker="+setup['ticker']+" setup_src="+setup['setup_src']
      #warnings.warn("msg",RuntimeWarning)
      return False
    setup['limit_price'] = short_limit_price_from_stop(setup['entry_stop_price'])
    print "short {tkr}, support {spt}, entry_stop {stp}, limit {lmt}".format(tkr=setup['ticker'],spt=setup['support'],stp=setup['entry_stop_price'],lmt=setup['limit_price'])
  else:
    setup['trailing_stop_type']  = setup.get('trailing_stop_type',"atr")
    print prices
    #print prices['close']
    #print prices['close'].values
    #print talib.MIN(prices['close'].values,5)
    #print round(talib.MIN(prices['close'].values,5)[-1],2)
    #setup['support']  = setup.get('support',None) or round(talib.MIN(prices['close'].values,5)[-1],2)
    #print "1 support {0}\n".format(setup['support'])
    setup['support']  = setup.get('support',round(talib.MIN(prices['close'].values,5)[-1],2))
    print "2 support {0}\n".format(setup['support'])
    if setup['support'] != setup['support']: setup['support']  = round(talib.MIN(prices['close'].values,2)[-1],2)
    print "3 support {0}\n".format(setup['support'])
    setup['entry_stop_price'] = setup.get('entry_stop_price',None) or long_entry_stop_price(prices)
    setup['limit_price'] = long_limit_price_from_stop(setup['entry_stop_price'])
    print "long {tkr}, support {spt}, entry_stop {stp}, limit {lmt}".format(tkr=setup['ticker'],spt=setup['support'],stp=setup['entry_stop_price'],lmt=setup['limit_price'])
  setup['tgt_gain_pts'] = 10
  setup['notes']       = ""
  setup['tags']        = set_tags(setup['ticker'],prices)
  setup['pyramid_pos'] = "true"
  setup['entry_signal'] = "pre-buy"
  setup['entry_filter'] = setup['entry_filter']
  return setup

