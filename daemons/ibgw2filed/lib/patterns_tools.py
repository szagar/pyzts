#import talib
from talib.abstract import *

BULLISH = 100
BEARISH = -100

def down_day(days_ago,prices):
  #print "down_day"
  try:
    day = (days_ago * -1) - 1
    prev_day = day - 1
    if ((prices['close'][day] - prices['close'][prev_day]) < -0.01):
      return True
    else:
      return False
  except Exception as e:
    print e.__doc__
    print e.message
    return False

def days_down(prices):
  #print "days_down"
  days_ago = 0
  while down_day(days_ago,prices):
    days_ago = days_ago + 1
  return days_ago

def pattern_five_days_down(prices):
  #print "pattern_five_days_down"
  if days_down(prices) >= 5:
    return BULLISH
  return None


def engulfing_white(prices):
  #print "engulfing_white"
  prev_low = min(prices['open'][-2],prices['close'][-2])
  prev_high = max(prices['open'][-2],prices['close'][-2])
  return (prices['close'][-1]>prev_high and prices['open'][-1]<prev_low)

def engulfing_black(prices):
  #print "engulfing_black"
  prev_low = min(prices['open'][-2],prices['close'][-2])
  prev_high = max(prices['open'][-2],prices['close'][-2])
  return (prices['close'][-1]<prev_low and prices['open'][-1]>prev_high)

def candle_stick_patterns(prices):
  tmp = {}
  rslt = pattern_EMA_25_50_200(prices)
  if rslt: tmp['EMA_25_50_200'] = rslt
  if pattern_five_days_down(prices) == BULLISH: tmp['5dd'] = BULLISH

  talib_patterns = { "CDL2CROWS":           CDL2CROWS,
                     "CDL3BLACKCROWS":      CDL3BLACKCROWS,
                     "CDL3INSIDE":          CDL3INSIDE,
                     "CDL3LINESTRIKE":      CDL3LINESTRIKE,
                     "CDL3OUTSIDE":         CDL3OUTSIDE,
                     "CDL3STARSINSOUTH":    CDL3STARSINSOUTH,
                     "CDL3WHITESOLDIERS":   CDL3WHITESOLDIERS,
                     "CDLABANDONEDBABY":    CDLABANDONEDBABY,
                     "CDLADVANCEBLOCK":     CDLADVANCEBLOCK,
                     "CDLBELTHOLD":         CDLBELTHOLD,
                     "CDLBREAKAWAY":        CDLBREAKAWAY,
                     "CDLCLOSINGMARUBOZU":  CDLCLOSINGMARUBOZU,
                     "CDLCONCEALBABYSWALL": CDLCONCEALBABYSWALL,
                     "CDLCOUNTERATTACK":    CDLCOUNTERATTACK,
                     "CDLDARKCLOUDCOVER":   CDLDARKCLOUDCOVER,
                     "CDLDOJI":             CDLDOJI,
                     "CDLDOJISTAR":         CDLDOJISTAR,
                     "CDLDRAGONFLYDOJI":    CDLDRAGONFLYDOJI,
                     "CDLENGULFING":        CDLENGULFING,
                     "CDLEVENINGDOJISTAR":  CDLEVENINGDOJISTAR,
                     "CDLEVENINGSTAR":      CDLEVENINGSTAR,
                     "CDLGAPSIDESIDEWHITE": CDLGAPSIDESIDEWHITE,
                     "CDLGRAVESTONEDOJI":   CDLGRAVESTONEDOJI,
                     "CDLHAMMER":           CDLHAMMER,
                     "CDLHANGINGMAN":       CDLHANGINGMAN,
                     "CDLHARAMI":           CDLHARAMI,
                     "CDLHARAMICROSS":      CDLHARAMICROSS,
                     "CDLHIGHWAVE":         CDLHIGHWAVE,
                     "CDLHIKKAKE":          CDLHIKKAKE,
                     "CDLHIKKAKEMOD":       CDLHIKKAKEMOD,
                     "CDLHOMINGPIGEON":     CDLHOMINGPIGEON,
                     "CDLIDENTICAL3CROWS":  CDLIDENTICAL3CROWS,
                     "CDLINNECK":           CDLINNECK,
                     "CDLINVERTEDHAMMER":   CDLINVERTEDHAMMER,
                     "CDLKICKING":          CDLKICKING,
                     "CDLKICKINGBYLENGTH":  CDLKICKINGBYLENGTH,
                     "CDLLADDERBOTTOM":     CDLLADDERBOTTOM,
                     "CDLLONGLEGGEDDOJI":   CDLLONGLEGGEDDOJI,
                     "CDLLONGLINE":         CDLLONGLINE,
                     "CDLMARUBOZU":         CDLMARUBOZU,
                     "CDLMATCHINGLOW":      CDLMATCHINGLOW,
                     "CDLMATHOLD":          CDLMATHOLD,
                     "CDLMORNINGDOJISTAR":  CDLMORNINGDOJISTAR,
                     "CDLMORNINGSTAR":      CDLMORNINGSTAR,
                     "CDLONNECK":           CDLONNECK,
                     "CDLPIERCING":         CDLPIERCING,
                     "CDLRICKSHAWMAN":      CDLRICKSHAWMAN,
                     "CDLRISEFALL3METHODS": CDLRISEFALL3METHODS,
                     "CDLSEPARATINGLINES":  CDLSEPARATINGLINES,
                     "CDLSHOOTINGSTAR":     CDLSHOOTINGSTAR,
                     "CDLSHORTLINE":        CDLSHORTLINE,
                     "CDLSPINNINGTOP":      CDLSPINNINGTOP,
                     "CDLSTALLEDPATTERN":   CDLSTALLEDPATTERN,
                     "CDLSTICKSANDWICH":    CDLSTICKSANDWICH,
                     "CDLTAKURI":           CDLTAKURI,
                     "CDLTASUKIGAP":        CDLTASUKIGAP,
                     "CDLTHRUSTING":        CDLTHRUSTING,
                     "CDLTRISTAR":          CDLTRISTAR,
                     "CDLUNIQUE3RIVER":     CDLUNIQUE3RIVER,
                     "CDLUPSIDEGAP2CROWS":  CDLUPSIDEGAP2CROWS,
                     "CDLXSIDEGAP3METHODS": CDLXSIDEGAP3METHODS  }

  #print prices
  #print "engulfing_white={ew}".format(ew=engulfing_white(prices))
  #print "engulfing_black={ew}".format(ew=engulfing_black(prices))
  for pat,fp in talib_patterns.iteritems():
    rslt = fp(prices)[-1]
    if abs(rslt) > 0:
      print "{p} :: {rslt}".format(p=pat,rslt=rslt)
      tmp[pat] = rslt
  return tmp


def pattern_EMA_25_50_200(prices):
  c = prices['close'][-1]
  ema25  = EMA(prices,25)[-1]
  ema50  = EMA(prices,50)[-1]
  ema200 = EMA(prices,200)[-1]
  #print "close   == {c}".format(c=prices['close'][-1])
  #print "EMA 25  == {ema}".format(ema=EMA(prices,25)[-1])
  #print "EMA 50  == {ema}".format(ema=EMA(prices,50)[-1])
  #print "EMA 200 == {ema}".format(ema=EMA(prices,200)[-1])
  #if c<ema25 and c<=ema50 and c<=ema200: print "pattern_EMA_25_50_200=BEARISH"
  if c<ema25 and c<=ema50 and c<=ema200: return BEARISH
  return None




