class EntryDarvasBuy
  attr_reader :name
  def initialize(args)
    @name = self.class
    @setups = []
  end
  
  def alert_buyStop
    { id: setup.entry_id, 
        event: 'bar5s', 
        params:   {
          sec_id: setup.sec_id, 
          alert: 'PriceAbove', 
          alert_px: setup.stop_px
        }
      }
  end
  
  def alert_config
    [ alert_buyStop ]
  end
  
  def add_setup(setup)
    setup.entry_id = SN.next_entry_id
    @setups << setup
    setup.add_entry(name)
    alert_config
  end
  
  def applicable?(setup)
    setup..members.member?(@name.to_sym)
  end
end



#  list == [  { id:     1,
#               event: 'bar5s', 
#               params: {   sec_id:     setup[:sec_id], 
#                            alert:      'PriceAbove', 
#                            alert_px:   setup[:stop_px]
#                       }
#              } 
#           ]
