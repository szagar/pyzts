import pandas.io.data as web
DEBUG = True

#Download data from yahoo finance
def yahoo_prices(ticker,start,end):
  if DEBUG: print "yahoo_prices({ticker},{start},{end})".format(ticker=ticker,start=start,end=end)
  try:
    prices = web.DataReader(ticker,'yahoo',start,end)
  except:
    return None
  return prices

import pandas as pd
import numpy as np
import urllib2
import datetime as dt
import matplotlib.pyplot as plt
Minute = 60
FiveMinute = Minute*5
Hourly = Minute*60
 
def get_google_data(symbol, period, window):
    url_root = 'http://www.google.com/finance/getprices?i='
    url_root += str(period) + '&p=' + str(window)
    url_root += 'd&f=d,o,h,l,c,v&df=cpct&q=' + symbol
    response = urllib2.urlopen(url_root)
    data = response.read().split('\n')
    #actual data starts at index = 7
    #first line contains full timestamp,
    #every other line is offset of period from timestamp
    parsed_data = []
    anchor_stamp = ''
    end = len(data)
    for i in range(7, end):
        cdata = data[i].split(',')
        if 'a' in cdata[0]:
            #first one record anchor timestamp
            anchor_stamp = cdata[0].replace('a', '')
            cts = int(anchor_stamp)
        else:
            try:
                coffset = int(cdata[0])
                cts = int(anchor_stamp) + (coffset * period)
                parsed_data.append((dt.datetime.fromtimestamp(float(cts)), float(cdata[1]), float(cdata[2]), float(cdata[3]), float(cdata[4]), float(cdata[5])))
            except:
                pass # for time zone offsets thrown into data
    df = pd.DataFrame(parsed_data)
    df.columns = ['ts', 'o', 'h', 'l', 'c', 'v']
    df.index = df.ts
    del df['ts']
    return df

def get_spread(base, hedge, ratio, period, window):
    b = get_google_data(base, period, window)
    h = get_google_data(hedge, period, window)
    combo = pd.merge(pd.DataFrame(b.c), pd.DataFrame(h.c), left_index = True, right_index = True, how = 'outer')
    combo = combo.fillna(method = 'ffill')
    combo['spread'] = combo.ix[:,0] + ratio * combo.ix[:,1]
    return(combo)

def add_ema(df,period):
    df['ewma'] = pd.ewma(df["c"], span=period)  #, freq="D")
    return df

def add_avg_range(df,period):
    df['r'] = df.ix[:,'h'] - df.ix[:,'l']
    df['ar'] = pd.ewma(df['r'], span=period)
    return df

#spy = get_google_data('SPY', FiveMinute, 10)
#print spy

#sprd = get_spread("SSYS", "DDD", -2.0, Hourly, 15)
#print sprd

#sune = get_google_data('SUNE', Hourly, 60)
#sune = add_ema(sune,50)
#print sune

