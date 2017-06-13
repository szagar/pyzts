module MiscHelper
  def self.first_numeric(*candidates)
    candidates.each do |c|
      return c.to_f if is_a_number?(c)
    end
    false
  end  

  #def self.first_pos_numeric(*candidates)
  def self.first_pos_numeric(candidates)
    candidates.each do |c|
      return c.to_f if is_a_number?(c) && c > 0
      #rescue next
    end
    false
  end  

  def self.is_a_number?(s)
    s.to_s.match(/\A[+-]?\d+?(\.\d+)?\Z/) == nil ? false : true 
  end

  def self.is_number?(s)
    s.to_f.to_s == s.to_s || s.to_i.to_s == s.to_s
  end

  def self.is_an_integer?(s)
    s.to_s.match(/\A[+-]?\d+?\Z/) == nil ? false : true 
  end

  def self.valid_price?(price)
    #(price.is_a?(Numeric) && price > 0.0)
    (is_a_number?(price) && price.to_f.round(2) > 0.0)
  end

  def self.valid_id?(id)
    #(id.is_a?(Integer) && id > 0)
    (is_an_integer?(id) && id.to_i > 0)
  end

end
