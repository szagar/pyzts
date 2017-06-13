class MySignal
  attr_accessor :ref_id, :var, :level, :op, :desc, :active
  def initialize(parms)
    @ref_id = parms[:ref_id]
    @var    = parms[:variable]
    @level  = parms[:level]
    @op     = parms[:operator]
    @desc   = parms[:desc] || "generic signal"
    @active = true
  end
  def check_bar(bar)
    bar[var.to_s].to_f.send op, level.to_f
  end
  def to_s
    "(#{ref_id}) #{var} #{op} #{level} #{active} \'#{desc}\'"
  end
  def self.from_hash(attributes)
    instance = self.new
    attributes.each do |key, value|
      next unless self.members.include?(key.to_sym)
      instance[key] = value
    end
    instance
  end
  def attributes(fields=members)
    result = {}
    fields.each do |name|
      result[name] = self[name]
    end
    result
  end
  
end
