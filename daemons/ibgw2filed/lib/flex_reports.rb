require 'ib-ruby'
require 'log_helper'

class FlexReports
  include LogHelper
  def initialize
    @config_file = "#{ENV['ZTS_HOME']}/etc/flex.yml"
  end

  def positions_data(account_name)
    debug "FlexReports#positions_data(#{account_name})"
    query_name = account_name + "_" + "positions"
    report = load_report_data(query_name)
  end

  def trade_date_activity(account_name)
    debug "FlexReports#trade_date_activity(#{account_name})"
    query_name = account_name + "_" + "activity"
    report = load_report_data(query_name)
  end

  def ytd_activity(account_name)
    debug "FlexReports#ytd_activity(#{account_name})"
    query_name = account_name + "_" + "activity" + "_20150106"
    report = load_report_data(query_name)
  end

  def prev_bday_confirms(account_name)
    debug "FlexReports#prev_bday_confirms(#{account_name})"
    query_name = account_name + "_" + "confirms"
    report = load_report_data(query_name)
  end

  private

  def load_query(query_name)
    if File.exists? @config_file
      query = YAML::load_file(@config_file)[query_name]
      raise "FLEX error: no query #{query_name} in #{@config_file}" unless query
      raise "FLEX error: no token/query_id for #{query_name}" unless query[:token] && query[:query_id]
    else
      raise "Flex config file: #{@config_file} not found"
    end
    query
  end

  def load_report_data(query_name)
    @retries ||= 0
    query = load_query(query_name)
    report = IB::Flex.new(query).run
  rescue =>e
    @retries += 1
    puts "IB retry: #{@retries}==>#{e}"
    raise e if @retries > 1
    sleep 2
    load_report_data(query_name)
  end
end
