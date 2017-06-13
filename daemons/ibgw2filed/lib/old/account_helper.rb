require 'redis_account'
require 'redis_position'
require 'account'

module AccountHelper
  extend self 

  def instantiate_account(name)
    account = Account.new
    account.get(name)
    account
  end

  def open_positions(account_name)
    RedisAccount.open_positions(account_name)
  end

  def open_positions_in_sec_id(account_name, sec_id)
    RedisAccount.open_positions(account_name).select { |pos_id|
      #puts "=>#{sec_id}"
      #puts "==>#{RedisPosition.sec_id(pos_id)}" 
      (RedisPosition.sec_id(pos_id) == sec_id.to_s)
    }
  end
end
