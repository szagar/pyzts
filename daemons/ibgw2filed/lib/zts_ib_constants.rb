module ZTS
  module IB
    Actions = Hash.new
    Actions["BOT"] = "buy"
    Actions["SLD"] = "sell"
    
    def IB.action(ib)
      puts "ZTS::IB::action(#{ib})"
      Actions[ib] 
    end
  end
end

    