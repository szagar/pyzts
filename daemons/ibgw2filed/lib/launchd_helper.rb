module LaunchdHelper
  STDOUT.sync = true
  def time_stamp; "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')}"; end
  def lstderr(str=""); $stderr.puts "[#{time_stamp}/#{File.basename($PROGRAM_NAME,".rb")}] #{str}"; end
  def lstdout(str=""); $stdout.puts "[#{time_stamp}/#{File.basename($PROGRAM_NAME,".rb")}] #{str}"; end
  
  def archive_file(archive_dir, fn)
    archive_file = "#{archive_dir}/#{File.basename(fn)}"
    if File.exist?(archive_file) then
      cnt = 1
      archive_file << ".#{cnt}"
      while File.exist?(archive_file) do
        archive_file = File.join(archive_dir,File.basename(archive_file, ".#{cnt}"))
        cnt += 1
        archive_file << ".#{cnt}"
      end
    end
    lstdout "File.rename #{fn}, #{archive_file}"
    File.rename fn, archive_file
    archive_file
  end  
end
