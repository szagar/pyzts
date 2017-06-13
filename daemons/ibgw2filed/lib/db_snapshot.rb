require "my_config"
require "log_helper"

class DbFills < ActiveRecord::Base
end
class DbOrders < ActiveRecord::Base
end
class DbPositions < ActiveRecord::Base
end
class DbAccounts < ActiveRecord::Base
end
class BrokerAccounts < ActiveRecord::Base
end
class BrokerPositions < ActiveRecord::Base
end

class DbSnapshot
  include LogHelper

  attr_accessor :today

  def initialze
    Zts.configure do |config|
      config.setup
    end

    @today = Date.today.strftime('%Y%m%d')

    ar_logname = config.dir_log + File.basename(__FILE__, ".rb")+'.log'
    puts "ar_logname=#{ar_logname}"
    ActiveRecord::Base.logger = Logger.new(ar_logname)
    ActiveRecord::Base.configurations = YAML::load(IO.read(config.dir_config + "/database.yml'))
    ActiveRecord::Base.establish_connection('development')
    ar_logger = Logger.new(ar_logname)
    ar_logger.datetime_format = '%Y-%m-%d %H:%M:%S'
    ar_logger.level = Logger::INFO   #  DEBUG INFO WARN ERROR FATAL
  end

  def account_snapshots
    AccountManager.accounts.each do |account|
      DbAccounts.find_or_create_by_account_name_and_asof(account.account_name,today).update_attributes(account.db_params)
    end
  end
end
