#!/usr/bin/env ruby
$: << "#{ENV['ZTS_HOME']}/lib"
require "store_mixin"
require "watchlist"

class WatchlistMgr
  include Store

  def initialize
    @watch_lists = {}
  end

  def list(search_str="*")
    (redis_md.keys "watchlist:#{search_str}").map { |k| k[/watchlist:(.*)/,1] }
  end

  def member_of(tkr)
    list.select { |wl| watch_list(wl).is_member?(tkr) }
  end

  def load_from_file(w_name,f_name)
    File.foreach(f_name) { |tkr| watch_list(w_name).add(tkr.chomp!) }
  end

  def add_to_watchlist(w_name,tkr)
    watch_list(w_name).add(tkr)
  end

  def rm_from_watchlist(w_name,tkr)
    watch_list(w_name).rm(tkr)
  end

  private

  def watch_list(name)
    @watch_lists[name] ||= Watchlist.new(name)
  end
end

=begin
  def list(type="*")
    if type == "mca"
      result = mca_list
    else
      (redis_md.keys "watchlist:#{type}").map { |k| k[/watchlist:(.*)/,1] }
    end
  end

  private

  def mca_list
    redis_md.lrange "watchlist:mca", 0, -1
  end
end
=end
