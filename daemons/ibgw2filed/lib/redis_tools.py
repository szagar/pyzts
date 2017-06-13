import os
import yaml
import redis as Redis

class ZtsRedis:

  def __init__(self, env):
    self.env = env
      
    self.cfg = self.load_config(env)

    ZtsRedis.conn    = self.redis()
    ZtsRedis.md_conn = self.redis_md()
    
  def load_config(self,env):
    print "Entered ZtsRedis.load_config !!!!!!!!!!!"
    cfg_file = os.environ["ZTS_HOME"] + "/etc/config.yml"
    with open(cfg_file, "r") as ymlfile:
      cfg = yaml.load(ymlfile)
    return cfg[env]

  def connect(self,host,db):
    print "Entered ZtsRedis.connect !!!!!!!!!!!"
    conn = Redis.StrictRedis(host=host, db=db)
    return conn

  def redis_md(self):
    print "Entered ZtsRedis.redis_md !!!!!!!!!!!"
    cfg = self.cfg['redis_md']
    conn = self.connect(host=cfg['host'], db=cfg['db'])
    return conn
    
  def redis(self):
    print "Entered ZtsRedis.redis !!!!!!!!!!!"
    cfg = self.cfg['redis']
    conn = self.connect(host=cfg['host'], db=cfg['db'])
    return conn

  def queue_setups(self):
    print "Entered ZtsRedis.queue_setups !!!!!!!!!!!"
    q = self.cfg['redis']['queue_setups']
    return q

  def next_setup_id(self):
    setup_id = ZtsRedis.conn.incr("seq:setup_id")
    return setup_id

  def req_md(self,sid):
    ZtsRedis.md_conn.sadd("md:subs", sid)

  def lookup_sid_id(self,ticker):
    key = "tkrs:" + ticker
    sid = ZtsRedis.md_conn.get(key)
    return sid


