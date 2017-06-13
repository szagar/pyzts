$: << "#{ENV['ZTS_HOME']}/etc"

require 'alert_store'

class  AlertProxy
  
#  def initialize(persister=AlertStore)
#    @persister = persister
#  end
  def initialize(params, persister=AlertStore)
    @persister = persister
    @alert_id = create_alert(params)
  end

  #def get_alert(id)
  #  @alert_id = id
  #end
  
  def create_alert(params)
    set_defaults(params)
    @alert_id = @persister.create(params)
  end

  def valid?
    true #(ref_id.is_a? Integer) && (sec_id.is_a? Integer)
  end

  def info
    persister_name
  end

  def dump
    @persister.dump(@alert_id)
  end

  def sec_id
    @sec_id
  end

  def alert_id
    @alert_id
  end

  def lvl
    @persister.getter(@alert_id,"lvl").to_f
  end

  def sec_id
    @persister.getter(@alert_id,"sec_id").to_i
  end

  def ref_id
    @persister.getter(@alert_id,"ref_id").to_i
  end

  private

  def persister_name
    @persister.whoami
  end

  def set_defaults(params)
    #params[:tif]             ||= :day
    #params[:status]          ||= 'init'
  end
end

