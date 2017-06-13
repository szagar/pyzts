class NullObject
  def method_missing(*args, &block)
    self
  end
  def nil?; end
end
def Maybe(value)
  value.nil? ? NullObject.new : value
end

