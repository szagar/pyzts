module Zts
  class << self
    attr_accessor :conf
  end

  def self.configure(zts_env=ENV['ZTS_ENV'])
    #self.conf ||= Conf.new(zts_env)
    self.conf = Conf.new(zts_env)
    yield(conf)
  end

  class Conf
    attr_accessor :redis_host, :redis_port, :redis_database
    attr_accessor :redis_mktdata_host, :redis_mktdata_port, :redis_mktdata_database
    attr_accessor :redis_master, :redis_db_paper, :redis_db_prod, :redis_db_dev,  :redis_db_md
    attr_accessor :amqp_host,      :amqp_port,      :amqp_vhost,      :amqp_user,      :amqp_pswd
    #attr_accessor :amqp_test_host, :amqp_test_port, :amqp_test_vhost, :amqp_test_user, :amqp_test_pswd, :amqp_test_exch
    #attr_accessor :amqp_prod_host, :amqp_prod_port, :amqp_prod_vhost, :amqp_prod_user, :amqp_prod_pswd, :amqp_prod_exch
    attr_accessor :amqp_md_host, :amqp_md_port, :amqp_md_vhost, :amqp_md_hb_int
    attr_accessor :amqp_md_user, :amqp_md_pswd
    attr_accessor :amqp_exch_mktdata,         :amqp_exch
    attr_accessor :amqp_exch_mktdata_options, :amqp_exch_options
    attr_accessor :amqp_exch_flow, :amqp_exch_core, :amqp_exch_db
    attr_accessor :zts_env
    attr_accessor :this_host
    attr_accessor :rt_alert, :rt_acct_balance
    attr_accessor :rt_bar5s, :rt_tick, :rt_bar_custom
    attr_accessor :rt_acct_position, :rt_setups, :rt_entry
    attr_accessor :rt_fills, :rt_submit, :rt_comm
    attr_accessor :rt_req_bar5s, :rt_unreq_bar5s
    attr_accessor :rt_open_order, :rt_order_status
    attr_accessor :rt_unwind, :rt_manual_stop
    attr_accessor :rt_lvc, :rt_admin
    attr_accessor :dir_log, :dir_config, :dir_reports
    attr_accessor :dir_run, :dir_mo, :dir_scripts
    attr_accessor :dir_inbox, :dir_archive, :dir_eod
    attr_accessor :dir_wlists
    attr_accessor :eod_host, :eod_user, :eod_passwd
    attr_accessor :eod_exchanges

    attr_accessor :execution_file

    def initialize(zts_env=ENV['ZTS_ENV'])
      @zts_env   = zts_env
      setup
    end

    def setup
      #@zts_env   = ENV['ZTS_ENV']
      @this_host = `hostname`.chomp[/(.*)\..*/,1]

      defaults
      env_specific(@zts_env)
      host4env_specific(@zts_env,@this_host)
    end

    private

    def amqp_routes
      @rt_admin          = "admin.#"
      @rt_manual_stop    = "manual.stop"
      @rt_entry          = "entry"
      @rt_setups         = "setups"
      @rt_req_bar5s      = "request.bar.5sec"
      @rt_unreq_bar5s    = "unrequest.bar.5sec"
      @rt_bar5s          = "md.bar.5sec"
      @rt_bar_custom     = "md.bar.custom"
      @rt_tick           = "md.tick"
      @rt_alert          = "data.alert"
      @rt_acct_balance   = "data.account.balance"
      @rt_acct_position  = "data.account.position"
      @rt_comm           = "data.commission"
      @rt_submit         = "flow.orders"
      @rt_fills          = "flow.fills"
      @rt_open_order     = "flow.ib.open_order"
      @rt_order_status   = "flow.order.state"
      @rt_unwind         = "signal.exit.stop"
      @rt_lvc            = "data.lvc"
    end

    def defaults
      @dir_run     = ENV["ZTS_HOME"] + "/etc/run"
      @dir_log     = ENV["ZTS_HOME"] + "/log"
      @dir_config  = ENV["ZTS_HOME"] + "/etc"
      @dir_inbox   = ENV["ZTS_HOME"] + "/data/inbox"
      @dir_wlists  = ENV["ZTS_HOME"] + "/data/watchlists"
      @dir_eod     = dir_inbox + "/eoddata"
      @dir_archive = ENV["ZTS_HOME"] + "/data/archive"
      @dir_reports = ENV["ZTS_HOME"] + "/data/reports"
      @dir_mo      = ENV["ZTS_HOME"] + "/data/middle_office"
      @dir_scripts = ENV["ZTS_HOME"] + "/scripts"

      @eod_host      = "ftp.eoddata.com"
      @eod_user      = "szagar"
      @eod_passwd    = "eoddata99"
      @eod_exchanges = %w(INDEX NYSE NASDAQ AMEX)

      @execution_file = "executions.json"

      amqp_routes

      @redis_master     = "appserver02.local"
      @redis_port       = "6379"
      @redis_db_paper   = "1"
      @redis_db_dev     = "2"
      @redis_db_md      = "8"
      @redis_db_prod    = "9"

      @redis_mktdata_host     = redis_master
      @redis_mktdata_port     = redis_port
      @redis_mktdata_database = redis_db_md

      @amqp_exch_mktdata         = "md_exch"
      @amqp_exch_mktdata_options = {durable: true, auto_delete: true}
      @amqp_exch_options         = {durable: true, auto_delete: true}

      @amqp_host                 = "appserver01.local"
      @amqp_port                 = "5672"
      @amqp_user                 = "guest"
      @amqp_pswd                 = "guest"

      @amqp_md_host              = "appserver01.local"
      @amqp_md_port              = "5672"
      @amqp_md_vhost             = "/zts_prod"
      @amqp_md_user              = "zts"
      @amqp_md_pswd              = "zts123"
      @amqp_md_hb_int            = 10

      @amqp_prod_host              = "appserver01.local"
      @amqp_prod_port              = "5672"
      @amqp_prod_vhost             = "/zts_prod"
      @amqp_prod_user              = "zts"
      @amqp_prod_pswd              = "zts123"
      @amqp_prod_exch              = "prod_exch"

      @amqp_test_host              = "appserver01.local"
      @amqp_test_port              = "5672"
      @amqp_test_vhost             = "/zts_test"
      @amqp_test_user              = "zts"
      @amqp_test_pswd              = "zts123"
      @amqp_test_exch              = "test_exch"

      @amqp_dev_host              = "localhost"
      @amqp_dev_port              = "5672"
      @amqp_dev_vhost             = "/zts_dev"
      @amqp_dev_user              = "zts"
      @amqp_dev_pswd              = "zts123"
      @amqp_dev_exch              = "dev_exch"
    end

    def env_specific(env)
      case env
      when "development"
        @redis_host        = "localhost"   # @redis_master
        @redis_database    = @redis_db_dev

        @redis_mktdata_host     = "localhost"
        @redis_mktdata_port     = redis_port
        @redis_mktdata_database = redis_db_md

        @amqp_host         = @amqp_dev_host
        @amqp_port         = @amqp_dev_port
        @amqp_vhost        = @amqp_dev_vhost
        @amqp_user         = @amqp_dev_user
        @amqp_pswd         = @amqp_dev_pswd
        @amqp_exch         = @amqp_dev_exch
        # amqp exchanges
        @amqp_exch_core    = @amqp_dev_exch
        @amqp_exch_flow    = @amqp_dev_exch
        @amqp_exch_db      = @amqp_dev_exch

        @amqp_md_host              = @amqp_dev_host    # "appserver01.local"
        @amqp_md_port              = "5672"
        @amqp_md_vhost             = @amqp_dev_vhost   # "/zts_prod"
        @amqp_md_user              = @amqp_dev_user
        @amqp_md_pswd              = @amqp_dev_pswd
      when "test"
        @redis_host        = @redis_master
        @redis_database    = @redis_db_paper

        @redis_mktdata_host     = "localhost"
        @redis_mktdata_port     = redis_port
        @redis_mktdata_database = redis_db_md

        @amqp_host         = @amqp_test_host
        @amqp_port         = @amqp_test_port
        @amqp_vhost        = @amqp_test_vhost
        @amqp_user         = @amqp_test_user
        @amqp_pswd         = @amqp_test_pswd
        # amqp exchanges
        @amqp_exch_core    = @amqp_test_exch
        @amqp_exch_flow    = @amqp_test_exch
        @amqp_exch_db      = @amqp_test_exch
        @amqp_exch         = @amqp_test_exch
      when "production"
        @redis_host        = @redis_master
        @redis_database    = @redis_db_prod
        @amqp_host         = @amqp_prod_host
        @amqp_port         = @amqp_prod_port
        @amqp_vhost        = @amqp_prod_vhost
        @amqp_user         = @amqp_prod_user
        @amqp_pswd         = @amqp_prod_pswd
        # amqp exchanges
        @amqp_exch_core    = @amqp_prod_exch
        @amqp_exch_flow    = @amqp_prod_exch
        @amqp_exch_db      = @amqp_prod_exch
        @amqp_exch         = @amqp_prod_exch
      end
    end

    def host4env_specific(env,host)
      case env
      when "development"
        case host
        when "macdaddy" 
       #   @redis_database = "2"
        end
      end
    end
  end

end
