class Vix
  attr_reader :dbh, :vix_id

  def initialize(dbh)
    @dbh = dbh
    @vix_id = 1459
  end

  def rank(period=250)
    high, low = max_min(period)
    vix = current_vix
    (vix - low) / (high - low) * 100
  end

  def last
    current_vix
  end

  ##################
  private
  ##################

  def current_vix
    sql = current_vix_sql
    results = dbh.exec_query(sql)
    results.first['close']
  end

  def max_min(period)
    sql = max_min_sql(period)
    results = dbh.exec_query(sql)
    [results.first['max_vix'], results.first['min_vix']]
  end

  def current_vix_sql
    <<-SQL.gsub /^\s*/, ""
    select close
      from idx_prices
     where index_id=#{vix_id}
      order by date desc
      limit 1
    SQL
  end

  def max_min_sql(period)
    no_recs = db_number_records
    period = (period <= no_recs) ? period : no_recs
    <<-SQL.gsub /^\s*/, ""
    select max(high) 'max_vix', min(low) 'min_vix'
      from idx_prices
     where index_id=#{vix_id}
       and date > (select date
                     from idx_prices I1
                    where index_id = #{vix_id}
                      and #{period} = (select count(*)
                                  from idx_prices I2
                                 where index_id = #{vix_id}
                                   and I1.date < I2.date  ))
    SQL
  end

  def db_number_records
    sql = "select count(*) 'cnt' from idx_prices where index_id=#{vix_id}"
    results = dbh.exec_query(sql)
    results.first['cnt'].to_i - 1
  end
end
