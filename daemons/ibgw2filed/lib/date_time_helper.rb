OPEN_IN_SECS = 34_200
CLOSE_IN_SECS = 57_600
NIGHTLY_HR    = 21
NIGHTLY_MIN   = 0

module DateTimeHelper
  def self.now
    Time.now
  end
  
  def self.integer_date(work_date=now)
    #Time.now.strftime('%Y%m%d')
    work_date.strftime('%Y%m%d')
  end

  def self.timestamp
    Time.now.to_s
  end

  def self.secs_to_open
    (market_open? ? 0 : secs_until_next_open)
  end

  def self.calc_secs_to_eod
    secs_until_next_close
  end

  def self.secs_until_nightly_process
    calc_secs_until_nightly_process
  end

  def self.secs_until_next_open
    today = now
    if ((1..5).include?(today.wday) and Time.now.to_i < mkt_open_today_secs(today) )
      secs_until_open
    else
      secs_until_next_day_open
    end
  end

  def self.secs_until_next_close
    today = now
    if ((1..5).include?(today.wday) and today.hour < 16 )
      secs_until_close
    else
      secs_until_next_day_close
    end
  end

  def self.secs_until_eow
    today = now
    if (today.wday == 5 and today.hour < 16 )
      secs_until_close
    else
      # SMZ - tmp, needs work
      secs_until_next_day_close
      #Time.new(ntd.year, ntd.mon, ntd.day, hour=16, min=0, sec=0)
    end
  end


  def self.market_open?(time=Time.now)
    secs, mins, hr = time.to_a
    time_in_secs = (((hr*60)+mins)*60)+secs
    ((1..5).include?(time.wday) and
      time_in_secs >= OPEN_IN_SECS  and
      time_in_secs <= CLOSE_IN_SECS )
  end

  def self.done_for_day_with_mktdata?
    #secs_since_midnight > (CLOSE_IN_SECS + 15 * 60)    # after 4:15pm?
    secs_since_midnight > CLOSE_IN_SECS    # after 4:00?
  end

  def self.secs2elapse(in_secs)
    hrs = in_secs/(60*60)
    mins = (in_secs-hrs*60*60)/60
    secs = in_secs - hrs*60*60 - mins*60
    #hrs > 0 ? ("%2.2d:%2.2d:%2.2d"%[hrs,mins,secs]) : ("%2.2d:%2.2d"%[mins,secs])
    "%2.2d:%2.2d:%2.2d"%[hrs,mins,secs]
  end

  def self.days(start_dt,end_dt)
    puts "0 start_dt = #{start_dt}/#{start_dt.class}"
    puts "0 end_dt   = #{end_dt}/#{end_dt.class}"
    puts "self.days(#{start_dt},#{end_dt})"
    puts "a: #{Date.strptime(end_dt.to_s,"%Y%m%d")}"
    puts "b: #{Date.strptime(start_dt.to_s,"%Y%m%d")}"
    puts "diff: #{Date.strptime(end_dt.to_s,"%Y%m%d") - Date.strptime(start_dt.to_s,"%Y%m%d")}"
    puts "diff: #{(Date.strptime(end_dt.to_s,"%Y%m%d") - Date.strptime(start_dt.to_s,"%Y%m%d")).to_i}"
    #puts "c: #{Time.strptime(end_dt.to_s,"%Y%m%d")}"
    #puts "d: #{Time.strptime(start_dt.to_s,"%Y%m%d")}"
    #(Time.strptime(end_dt.to_s,"%Y%m%d") -
    # Time.strptime(start_dt.to_s,"%Y%m%d")).to_i / (24*60*60) + 1
    (Date.strptime(end_dt.to_s,"%Y%m%d") -
     Date.strptime(start_dt.to_s,"%Y%m%d")).to_i
  rescue => e
    puts e
    puts "1 start_dt = #{start_dt}"
    puts "1 end_dt   = #{end_dt}"
    -1
  end

  private

  def self.secs_since_midnight(time=Time.now)
    secs, mins, hr = time.to_a
    time_in_secs = (((hr*60)+mins)*60)+secs
  end

  def self.next_trading_day_close
    ntd = now+60*60*24
    until ((1..5).include?(ntd.wday)) do
      ntd += 60*60*24
    end
    Time.new(ntd.year, ntd.mon, ntd.day, hour=16, min=0, sec=0)
  end

  def self.next_trading_day_open(work_date=now)
    ntd = work_date+60*60*24
    until ((1..5).include?(ntd.wday)) do
      ntd += 60*60*24
    end
    Time.new(ntd.year, ntd.mon, ntd.day, hour=9, min=30, sec=0)
  end

  def self.future_trade_day(n=1)
    @work_date = now
    n.times do 
      @work_date=next_trading_day_open(@work_date)
    end
    integer_date(@work_date)
  end

  def self.secs_until_close
    today = now
    (Time.new(today.year, today.mon, today.day, hour=16, min=0, sec=0) - today).to_i
  end

  def self.secs_until_next_day_close
    (next_trading_day_close - now).to_i
  end

  def self.calc_secs_until_nightly_process
    ntd = today = now
    ntd += 60*60*24 if ntd.hour >= NIGHTLY_HR
    until ((1..5).include?(ntd.wday)) do
      ntd += 60*60*24
    end
    (Time.new(ntd.year, ntd.mon, ntd.day, hour=NIGHTLY_HR, min=NIGHTLY_MIN, sec=0) - today).to_i
  end

  def self.secs_until_open
    today = now
    (Time.new(today.year, today.mon, today.day, hour=9, min=30, sec=0) - today).to_i
  end

  def self.secs_until_next_day_open
    (next_trading_day_open - now).to_i
  end

  def self.mkt_open_today_secs(today)
    Time.local(today.year,today.month,today.day,9,30,0).to_i
  end
end
