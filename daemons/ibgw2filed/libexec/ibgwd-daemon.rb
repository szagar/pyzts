require "ib_gw_2file" 
# Do your post daemonization configuration here
# At minimum you need just the first line (without the block), or a lot
# of strange things might start happening...
DaemonKit::Application.running! do |config|
  # Trap signals with blocks or procs
  # config.trap( 'INT' ) do
  #   # do something clever
  # end
  # config.trap( 'TERM', Proc.new { puts 'Going down' } )
end

# Ensure graceful shutdown of the connection to the broker
DaemonKit.trap('INT') { ::AMQP.stop { ::EM.stop } }
DaemonKit.trap('TERM') { ::AMQP.stop { ::EM.stop } }

DaemonKit.logger.level = :info

opts = {}
broker = ARGV[0]
opts[:ib_app] = ARGV[1] if ARGV[1]

def start_broker(broker, opts)
  ibgw = IbGw.new(broker, opts)
  zts_data = "/Users/szagar/Dropbox/zts"
  playbook = "#{zts_data}/playbook.txt"
  EventMachine.next_tick do
    DaemonKit.logger.info "Config ..."
    #ibgw.start_ewrapper
    #ibgw.subscribe_admin
    #ibgw.watch_for_new_orders
    #ibgw.watch_for_md_requests   if ibgw.active_mkt_data_server?
    #ibgw.watch_for_md_unrequests if ibgw.active_mkt_data_server?

    puts "ibgw.query_account_data"
    ibgw.query_account_data

    File.open(playbook,"r").each { |tkr| ibgw.subscribe_ticks(tkr.chomp) } if File.exists?(playbook)
    #puts "@thread_id = Thread.new {"
    #@thread_id = Thread.new {
    #  EventMachine::run {
    #    EventMachine::start_server "127.0.0.1", 8081, IbGw
    #    puts 'running echo server on 8081'
    #  }
    #}
  end
  ibgw.thread_id.join
  #@thread_id.join
end

ibgw = start_broker(broker,opts)
