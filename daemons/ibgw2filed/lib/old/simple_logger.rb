module SimpleLogger
  def simpleLoggerSetup(proc_name=File.basename($PROGRAM_NAME,".rb"))
    @proc_name = proc_name
    STDOUT.sync = true
  end
  def time_stamp; "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')}"; end
  def info(str="");  $stderr.puts "[INF:#{time_stamp}/#{@proc_name}] #{str}"; end
  def warn(str="");  $stderr.puts "[WRN:#{time_stamp}/#{@proc_name}] #{str}"; end
  def debug(str=""); $stderr.puts "[DBG:#{time_stamp}/#{@proc_name}] #{str}"; end
  def talk(str="");  $stderr.puts "[TLK:#{time_stamp}/#{@proc_name}] #{str}"; end
end
