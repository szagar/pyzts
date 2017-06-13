from redis_tools import ZtsRedis
#import __main__
#redis = __main__.redis
#kredis = ZtsRedis(zts_env)

def watchlists():
  list = ["ibd50", "sector_leaders", "bigcap20", "bir", "smallcap_leaders", "bolting_rs",
          "fin_eff", "internet", "acc_mf", "young_guns", "est_beaters", "rising_est",
          "mkt_eff", "profit_margin", "focus_list", "focus_etfs",
          "short_test", "swing_short", "upside_action", "s_down_action", "s_scans"]
  return list

def watchlist_membership(tkr):
  mship = []
  for watchlist in watchlists():
    if ZtsRedis.md_conn.sismember(watchlist,tkr):
      name = watchlist[len("watchlist:"):]
      mship.append(watchlist[len("watchlist:"):])
  return mship

def ticker_list(watchlist):
  print "ticker_list(%s):" % watchlist
  key = "watchlist:" + watchlist
  #print "ZtsRedis.__dict__:", ZtsRedis.__dict__
  tickers = ZtsRedis.md_conn.smembers(key)
  return tickers

def is_short_watchlist(watchlist):
  #print "is_short_watchlist"
  if ("short" in watchlist.lower()): return True
  if (watchlist.startswith("s_")): return True
  return False

#def long_entry_stop_price(prices):
#  work_price = prices['high'][-1]
#  px_adj = (0.25 if (work_price >= 10) else 0.125)
#  if work_price < 5.0: px_adj = 0.06
#  return round(work_price+px_adj,2)

#def short_limit_price_from_stop(stop_price):
#  px_adj = 0.38
#  return round(stop_price-px_adj,2)

#def long_limit_price_from_stop(stop_price):
#  px_adj = (0.38 if (stop_price >= 10) else 0.25)
#  if stop_price < 5.0: px_adj = 0.12
#  return round(stop_price+px_adj,2)


