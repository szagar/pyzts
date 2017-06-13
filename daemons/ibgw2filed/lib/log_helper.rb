module LogHelper

  DEBUG = 10
  INFO  = 20
  ACTN  = 30
  WARN  = 40
  ERROR = 50
  FATAL = 60
  $zts_log_level = INFO
  #$zts_log_level = DEBUG

  STDOUT.sync = true
  def time_stamp; "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')}"; end

  def alert str
    $stderr.puts "ALRT:#{time_stamp}  #{str}" if $zts_log_level <= ACTN
  end

  def warn str
    $stderr.puts "WARN:#{time_stamp}  #{str}" if $zts_log_level <= WARN
  end

  def track str
    $stderr.puts "TRCK:#{time_stamp}  #{str}" if $zts_log_level <= ACTN
  end

  def action str
    $stderr.puts "ACTN:#{time_stamp}  #{str}" if $zts_log_level <= ACTN
  end

  def show_action str
    action str
  end

  def show_info str
    $stdout.puts "INFO:#{time_stamp}  #{str}" if $zts_log_level <= INFO
  end

  def show_status str
    $stdout.puts "STAT:#{time_stamp}  #{str}" if $zts_log_level <= INFO
  end

  def debug str
    $stdout.puts "DBUG:#{time_stamp}  #{str}" if $zts_log_level <= DEBUG
  end
end
