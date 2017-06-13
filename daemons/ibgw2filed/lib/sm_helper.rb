$: << "#{ENV['ZTS_HOME']}/etc"

require 'active_record'
require 'logger'
#require 'zts_config'

ActiveRecord::Base.logger = Logger.new($stdout)
ActiveRecord::Base.configurations = YAML::load(IO.read(ENV['ZTS_HOME'] + '/etc/database.yml'))
ActiveRecord::Base.establish_connection('development')

module SmHelper

  def n_day_high(days,tkr)
    sql = <<SQL
    SELECT max(a.high) high_price
      FROM sm_prices AS a, sm_tkrs AS t
     WHERE t.tkr = '#{tkr}'
       AND t.sec_id = a.sec_id
       and (SELECT COUNT(*)
              FROM sm_prices AS b
             WHERE b.sec_id = a.sec_id
               AND b.date >= a.date) <= #{days}
    ORDER BY a.date ASC
SQL

    results = ActiveRecord::Base.connection.exec_query(sql)
    high_price = results.first['high_price']
  end

  def n_day_low(days,tkr)
    sql = <<SQL
    SELECT min(a.low) low_price
      FROM sm_prices AS a, sm_tkrs AS t
     WHERE t.tkr = '#{tkr}'
       AND t.sec_id = a.sec_id
       and (SELECT COUNT(*)
              FROM sm_prices AS b
             WHERE b.sec_id = a.sec_id
               AND b.date >= a.date) <= #{days}
    ORDER BY a.date ASC
SQL

    results = ActiveRecord::Base.connection.exec_query(sql)
    low_price = results.first['low_price']
  end

end
