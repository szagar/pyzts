from redis_tools import ZtsRedis

def lookup_sid_id(ticker):
  key = "tkrs:" + ticker
  sid = ZtsRedis.md_conn.get(key)
  return sid


