require 'fileutils'

module FileHelper
  def archive_file(archive_dir, fn, date_option=false)
    archive_file = "#{archive_dir}/#{File.basename(fn)}"
    archive_file = "#{archive_file}.#{Time.now.strftime('%Y%m%d')}" if date_option
    if File.exist?(archive_file) then
      cnt = 1
      archive_file << ".#{cnt}"
      while File.exist?(archive_file) do
        archive_file = File.join(archive_dir,File.basename(archive_file, ".#{cnt}"))
        cnt += 1
        archive_file << ".#{cnt}"
      end
    end
    $stderr.puts "File.rename #{fn}, #{archive_file}"
    File.rename fn, archive_file
    archive_file
  end  

  def queue_for_db_load(queue, fn, ticker)
    puts "queue_for_db_load(#{queue}, #{fn}, #{ticker})"
    system 'mkdir', '-p', queue
    lnk_file = "#{queue}/#{ticker}.txt"
    File.delete(lnk_file) if File.symlink?(lnk_file)
    File.symlink(fn, lnk_file)
  rescue => e
    warn e.message
  end

  def copy_file_force(src,dest)
    working_dir = File.dirname(dest)
    system 'mkdir', '-p', working_dir
    File.delete(dest) if File.exists?(dest)
    FileUtils.cp(src, dest)
  end

  def copy_file(src,dest)
    File.delete(dest) if File.exists?(dest)
    FileUtils.cp(src, dest)
  end
end
