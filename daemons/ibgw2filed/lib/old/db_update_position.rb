$: << "#{ENV['ZTS_HOME']}/db/models"
$: << "#{ENV['ZTS_HOME']}/lib"

require 'db_positions'
require 'fill'

class DbUpdatePosition
  def close_pos(pos_id)
    realized = DbPositions.calc_realized(pos_id)
    puts "realized = #{realized}"
    pos = DbPositions.find_by_pos_id(pos_id)
    puts "pos.class = #{pos.class}"
    puts "pos.inpsect = #{pos.inspect}"
    pos.realized = realized
    pos.save
  end
  
  def buy(fill)
    puts "fill.class  is #{fill.class}"
    DbFills.create(fill.db_parms)
    pos_id = fill.pos_id
    pos = DbPositions.find_by_pos_id(pos_id)
    pos.send(fill.action, fill.qty, fill.price)
  end

  def update_unrealized
    puts "DbPositions#update_unrealized"
    price = 100
    DbPositions.open.each do |pos|
      sec_id  = pos.sec_id
      puts "sec_id = #{sec_id}"
      side    = pos.side
      puts "side = #{side}"
    
      pos.quantity = DbPositions.quantity_from_fills(pos.pos_id)
      puts "pos.quantity = #{pos.quantity}"
      pos.avg_price = DbPositions.avg_price_from_fills(pos.pos_id)
      puts "pos.avg_price = #{pos.avg_price}"
      pos.unrealized = (price - pos.avg_price) * pos.quantity
      puts "pos.unrealized = #{pos.unrealized}"
      pos.save
    end
  end
end

