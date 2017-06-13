#!/usr/bin/env zts_ruby

$: << "#{ENV['ZTS_HOME']}/lib"
require "portfolio_mgr"
require "risk_mgr"
require "account_proxy"
require "s_m"
require "last_value_cache"

BrokerLookup = { "smz_prod"  => "smz_prod",
                  "smz_paper" => "smz_paper" }

class ManualPosition
  def initialize
    @accounts = {}
    @portf_mgr  = PortfolioMgr.instance
    @rmgr       = RiskMgr.new
    @lvc        = LastValueCache.instance
    @sec_master = SM.instance
  end

  def config_position(params)
    sec_id     = @sec_master.sec_lookup(params[:ticker])
    atr        = @lvc.atr(sec_id).to_f
    atr_factor = (params[:trade_type] == "Swing") ? 1.0 : 2.7
    risk_share = params.fetch(:risk_share) { (atr*atr_factor).round(2) }
    params = { :account_name       => params[:account_name],
      :ticker             => params[:ticker],
      :sec_id             => sec_id,
      :atr                => atr,
      :atr_factor         => (params[:trade_type] == "Swing") ? 1.0 : 2.7,
      :broker             => params[:broker] || BrokerLookup[account_name],
      :quantity           => params[:qty].to_i,
      :price              => params[:price].to_f,
      :side               => params[:side],
      :trailing_stop_type => "atr",
      :init_risk_position => params[:init_risk_position] || (risk_share*params[:qty]).round(2),
      :current_risk_share => risk_share,
      :commissions        => params[:comm] || 0,
      :setup_src          => "manual",
      :entry_signal       => "DNK",
      :trade_type         => params[:trade_type],
      :init_risk_share    => risk_share,
      :init_risk_position => params[:init_risk_position],
    }
    params
  end

  def account(position_h)
    acct_name = position_h[:account_name]
    #@accounts[acct_name] ||= (AccountProxy.new(account_name: acct_name))
    @accounts[acct_name] ||= (AccountProxy.new(position_h))
  end

  def create_position(pos)
    puts "create_position(#{pos})"
    pos_id = @portf_mgr.create_manual_position(pos)
    pos    = @portf_mgr.position(pos_id)
    pos.mark(@lvc.last(pos.sec_id))
    @rmgr.update_trailing_stop(pos_id)
  end
end

