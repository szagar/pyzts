import pandas.io.data as web
DEBUG = True if not Debug

def next_setup_id():
  global redis
  setup_id = redis.incr("seq:setup_id")
  return setup_id


