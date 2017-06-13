BarStruct = Struct.new( :mkt, :sec_id, :time, :open, :high, :low, :close,
                        :volume, :wap, :trades ) do
  def self.from_hash(attributes)
    instance = self.new
    attributes.each do |key, value|
      next unless self.members.include?(key.to_sym)
      instance[key] = value
    end
    instance
  end
  
  def attributes
    result = {}
    members.each do |name|
      result[name] = self[name]
    end
    result
  end
  
  def clear
    high   = 0.0
    low    = 0.0
    volume = 0
    trades = 0
  end

  def to_human
    "#{time.to_i} | #{Time.at(time.to_i).strftime("%H:%M:%S")} (#{mkt}:#{sec_id})  H/L: #{high}/#{low}   O/C: #{open}/#{close}   wap: #{wap}  V/T: #{volume}/#{trades}"
  end
end
