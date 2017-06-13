#$: << "#{ENV['ZTS_HOME']}/etc"
require "store_mixin"
require "zts_constants"
require "log_helper"
require "s_n"
#require "redis_store"

class TransactionStore # < RedisStore
  include Singleton
  include Store
  include ZtsConstants
  include LogHelper
  
  attr_reader :sequencer

  def initialize
    @sequencer = SN.instance
    super
  end

  def deposit(account_name, amount, date, note="")
    write("deposit", account_name, amount, date, note)
    amount
  end

  def withdraw(account_name, amount, date, note="")
    write("withdraw", account_name, amount, date, note)
    amount
  end

  def by_account(account_name)
    redis.get (redis.smembers pk(account_name))
  end

  def by_type(account_name, xtype, count=1)
    by_account(account_name).select { |rec|
      rec[/xtype:*:*:*:*/,1]
    }
  end

  #######
  private
  #######

  def pk(account)
    "xact:#{account}"
  end

  def write(xtype, account_name, amount, date, note)
    # XACT:deposit 20140519 100000 to p_exit_tightest, note:
    action "XACT:#{xtype} #{date} #{amount} to #{account_name}, note: #{note}"
    redis.sadd pk(account_name),
              format_xact(xtype,account_name,date,amount,note)
  end

  def format_xact(xtype,account,date,amount,note)
    seqn = sequencer.next_xact_id
    [xtype,seqn,date,amount,note].join("|")
  end
end
