$: << "#{ENV['ZTS_HOME']}/etc"

require 'active_record'
require 'logger'
#require 'zts_config'


class BrokerPositions < ActiveRecord::Base
end
class BrokerAccounts < ActiveRecord::Base
end

class ZtsDb
  def initialize(config_file=nil)
    configure
  end

  def configure(config_file=ENV['ZTS_HOME'] + '/etc/' + 'database.yml')
    logname = ENV['ZTS_HOME'] + '/log/' + File.basename(__FILE__, ".rb")+'.log'
    ActiveRecord::Base.logger = Logger.new(logname)
    ActiveRecord::Base.configurations = YAML::load(IO.read(config_file))
  end

  def broker_account_list
    BrokerAccounts.find(:all).map do |account|
      puts "ZtsDbbroker_account_list: #{account.inspect}"
    end
  end

  def broker_account_positions(account)
    BrokerPositions.find_all_by_broker_account(account)
  end

  private

  def connection
    #ActiveRecord::Base.establish_connection('development')
    @connection ||= ActiveRecord::Base.connection('development')
  end
end
