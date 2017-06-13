require 'entry_base'
require 's_m'
require 'launchd_helper'

class EntryAtMkt < EntryBase
  include LaunchdHelper
  
  attr_reader :name
  
  def initialize(options={})
    super self.class, options
    @name = self.class.to_s[/Entry(.*)/,1]
  end
  
  def add_setup(setup)
    super
    
    EM.add_timer(5) do
      setup.price = (setup.action.eql?('buy')) ? SM.high(setup['sec_id']) : SM.low(setup['sec_id'])
      lstderr "SEND TRADE HERE"
      @send_entry.call(name,setup)
    end
  end
  
  def subscriptions(channel)
    #routing_key = "#{ZtsApp::Config::ROUTE_KEY[:data][:bar5s]}.#"
    #@amqp_channel.queue("", :auto_delete => true)
    #             .bind(@amqp_exchange, :routing_key => routing_key)
    #             .subscribe do |headers, payload|
    #  headers.routing_key[/md.bar.5sec\.(.*)\.(.*)/]
    #  mkt,sec_id = [$1, $2]
    #  check_breakouts(bar_struct.from_hash(JSON.parse(payload))) if(@sec_list.has_key?(sec_id))
    #end
  end
    
  #def applicable?(setup)
  #  setup..members.member?(@name.to_sym)
  #  true
  #end
  
  def qualify?(setup)
    super
    #(setup.ticker.eql?('STD')) ? true : false
    #@notifier.call 
  end
  
end

