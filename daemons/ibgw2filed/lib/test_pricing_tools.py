#!/usr/bin/env python

import pandas as pd
from pandas.tseries.offsets import BDay

import pricing_tools as pt

end = pd.datetime.today()
start = end - BDay(2)
tkr = 'MSFT'
prices = pt.yahoo_prices(tkr,start,end)
print prices
 
