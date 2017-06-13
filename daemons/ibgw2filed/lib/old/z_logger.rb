class ZLogger
  def debug(str)
    @local_log_filename = "zlog.log"
    File.open(@local_log_filename, 'a') {|f| f.write(str+"\n") }
  end
end

