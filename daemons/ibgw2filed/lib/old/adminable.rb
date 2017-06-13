require 'launchd_helper'

module Adminable
  include LaunchdHelper
  
  def seperator
    "===================================================\n"
  end
  
  def hdr 
    @hdr ||= Array.new
  end

  def set_hdr(str)
    hdr << str
    str
  end

  def write_hdr
    lstdout seperator
    hdr.map { |m| lstdout m }
    lstdout seperator  
  end
  
  def ignore_admin_all
    @stop_on_all ||= true
  end
  
  def stop_on_all
    @stop_on_all = ((@stop_on_all != nil) ? @stop_on_all : false)
    @stop_on_all
  end
  
  def clear_screen
    Screen.clear
    write_hdr
    begin
      show_after_header_hook
    rescue
    end
  end
  
  
  def watch_admin_messages(channel)
    #routing_key = ZtsApp::Config::ROUTE_KEY[:admin][:all]
    routing_key = Zts.conf.rt_admin
    #exchange = channel.topic(ZtsApp::Config::EXCHANGE[:core][:name], ZtsApp::Config::EXCHANGE[:core][:options])
    exchange = channel.topic(Zts.conf.amqp_exch_core,
                             Zts.conf.amqp_exch_options)
    hdr << "exchange(#{exchange.name}) bind(#{routing_key})\n"
    channel.queue("", :auto_delete => true).bind(exchange, :routing_key => routing_key).subscribe do |headers, payload|
      action = headers.routing_key[/admin\.(.*)/, 1]
      if (payload === "all" && ! stop_on_all) || payload == proc_name then
        case action
        when "stop"
          channel.connection.close { EventMachine.stop { exit } }
        when "clear"
          clear_screen
        when "break"
          lstdout seperator
        when "proc"
          lstdout proc_name
        when "config"
          begin
            push_config
          rescue
            lstderr "missing push_config, ignoring"
          end
        else
          lstderr "** admin message \'#{action}\' not recognized !!"
        end
      end
    end
  end
  
end
