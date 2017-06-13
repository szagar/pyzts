#!/usr/bin/env /Users/szagar/.rvm/bin/zts_ruby
# encoding: utf-8

require "dotenv"
Dotenv.load

$: << "#{ENV['ZTS_HOME']}/etc"
$: << "#{ENV['ZTS_HOME']}/lib"

require "my_config"
require "net/ftp"
require "log_helper"

class EodDataProblem < StandardError; end

class EodData
  include LogHelper

  attr_accessor :rhost, :ruser, :rpasswd, :ftp, :asof

  def initialize
    Zts.configure { |config| config.setup }
    @asof    = Time.now.strftime('%Y%m%d')
    @rhost   = Zts.conf.eod_host
    @ruser   = Zts.conf.eod_user
    @rpasswd = Zts.conf.eod_passwd
    @ftp     = eoddata_session
  end

  def set_asof(asof)
    @asof = asof
  end

  def ls
    eoddata_session { puts "====>ftp.ls" }
  end

  def download_eod_price_files(date = asof)
    prefix = "eod_price_"
    eoddata_session {
      Zts.conf.eod_exchanges.each do |exch|
      rfile = "#{exch}_#{date}.txt"
      lfile = "#{Zts.conf.dir_eod}/eod_price_#{rfile}"
      puts "get_file(#{rfile}, #{lfile})"
      get_file(rfile, local_dir + prefix + f)
      end
    }
  rescue Net::FTPPermError => err
    warn "FTP Problem: #{err.message}"
  rescue 
    warn "FTP problem getting remote file"
  end

  #####################
  private
  #####################

  def eoddata_session
    puts "Net::FTP.open(#{rhost}) {  |ftp|"
    Net::FTP.open(rhost) {  |ftp|
      login_eoddata(ftp)
      yield 
    }  
  rescue
    warn "could not connect to #{rhost}"
  end

  def login_eoddata(conn)
    puts "conn.login(user = #{ruser}, passwd = #{rpasswd})"
    conn.login(user = ruser, passwd = rpasswd)
  end

  def get_file(remote_fn, local_fn)
    ftp.gettextfile(remote_fn, local_fn)
  rescue 
    warn "FTP problem: ftp.gettextfile(#{remote_fn}, #{local_fn})"
  end
end

eod = EodData.new
eod.ls.each { |f| puts f }
date = ARGV[0] || asof
eod.download_eod_price_files(date)
