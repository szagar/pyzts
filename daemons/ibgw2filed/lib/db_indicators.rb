require "logger"
require "singleton"
require "my_config"
require "active_record"
require "vix"

class DbIndicators
  include Singleton

  attr_reader :dbh

  def initialize
    Zts.configure { |config| config.setup }
    @dbh = initialize_db
    @vix = Vix.new(dbh)
  end

  def vix_rank
    @vix.rank
  end

  def vix
    @vix.last
  end

  #############
  private
  #############

  def initialize_db
    #ActiveRecord::Base.logger = Logger.new($stdout)
    ActiveRecord::Base.configurations = YAML::load(IO.read(Zts.conf.dir_config + '/database.yml'))
    ActiveRecord::Base.establish_connection('development')
    ActiveRecord::Base.connection
  end
end

