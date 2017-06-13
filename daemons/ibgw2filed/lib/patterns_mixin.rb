module Patterns
  def nesting_white?(ago=0)
    top = prev("high",ago+1)
    bot = [prev("close",ago+1), prev("open",ago+1) ].max
    
    ( white_candle?(ago)      &&
      prev("open",ago) >= bot &&
      prev("close",ago) <= top   )
  end

  def engulfing_white?(ago=0)
    pmax = [prev("close",ago+1), prev("open",ago+1) ].max
    pmin = [prev("close",ago+1), prev("open",ago+1) ].min
    (white_candle?(ago) && ( prev("close",ago) > pmax ) && ( prev("open",ago) < pmin ))
  end

  def engulfing_black?(ago=0)
    pmax = [prev("close",ago+1), prev("open",ago+1) ].max
    pmin = [prev("close",ago+1), prev("open",ago+1) ].min

    ( black_candle?(ago)          &&
      ( prev("open",ago) > pmax ) &&
      ( prev("close",ago) < pmin )   )
  end

  def white_candle?(ago=0)
    prev("close",ago) > prev("open",ago)
  end

  def black_candle?(ago=0)
    prev("close",ago) < prev("open",ago)
  end

  def pattern_1?
    puts "1 #{prev("open",4)}  > #{prev("open",3)}  && "
    puts "2 #{prev("open",3)}  > #{prev("open",2)}  && "
    puts "3 #{prev("close",4)} < #{prev("open",3)}  && "
    puts "4 #{prev("close",3)} < #{prev("open",2)}  && "
    puts "5 #{prev("open",2)}  > #{prev("close",1)} && "
    puts "6 #{prev("close",2)} < #{prev("open",1)}  && "
    puts "7 #{prev("close",2)} < #{last("open")}    && "
    puts "8 #{prev("close",4)} > #{prev("close",3)} && "
    puts "9 #{prev("close",3)} > #{prev("close",2)} && "
    puts "0 #{last("open")}    < #{prev("open",1)}  && "
    puts "white_candle?    #{white_candle?}    && "
    puts "white_candle?(1) #{white_candle?(1)}"

    ( prev("open",4)  > prev("open",3)  &&
      prev("open",3)  > prev("open",2)  &&
      prev("close",4) < prev("open",3)  &&
      prev("close",3) < prev("open",2)  &&
      prev("open",2)  > prev("close",1) &&
      prev("close",2) < prev("open",1)  &&
      prev("close",2) < last("open")    &&
      prev("close",4) > prev("close",3) &&
      prev("close",3) > prev("close",2) &&
      last("open")    < prev("open",1)  &&

      white_candle?                     &&
      white_candle?(1)                       )  
  end

  def dd?(n)
    (1..n).each { |day| return false unless prev("close",day-1) < prev("close",day) }
    return true
  end

  def five_dd?
    dd?(5)
    #last("close")   < prev("close",1)  &&
    #prev("close",1) < prev("close",2)  &&
    #prev("close",2) < prev("close",3)  &&
    #prev("close",3) < prev("close",4)  &&
    #prev("close",4) < prev("close",5)
  end

  def inside_day?
    last("high")  < prev("high",1)  &&
    last("low")   > prev("low",1)
  end
  
  def five_dd_inside?
    five_dd? && inside_day?
  end

   def four_dd30?
     dd?(4) && (recent_return(4) <= 0.30)
   end 
end
