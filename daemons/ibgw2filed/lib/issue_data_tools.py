import pandas as pd
import urllib2
from bs4 import BeautifulSoup as bs
 
def get_short_interest(symbol):
  # D2C: days to cover
  # ADV: average daily share volume
  url = "http://www.nasdaq.com/symbol/" + symbol + "/short-interest"
  res = urllib2.urlopen(url)
  res = res.read()
  soup = bs(res)
  si = soup.find("div", {"id": "quotes_content_left_ShortInterest1_ContentPanel"})
  si = si.find("div", {"class": "genTable floatL"})
  df = pd.read_html(str(si.find("table")))[0]
  df.index = pd.to_datetime(df['Settlement Date'])
  del df['Settlement Date']
  df.columns = ['ShortInterest', 'ADV', 'D2C']
  return df.sort()

sune = get_short_interest("SUNE")
print sune
