#!usr/bin/ruby

module Enumerable

  def sum
    return self.inject(0){|accum, i| accum + i }
  end

  def mean
    return self.sum / self.length.to_f
  end

  def sample_variance
    m = self.mean
    sum = self.inject(0){|accum, i| accum + (i - m) ** 2 }
    return sum / (self.length - 1).to_f
  end

  def standard_deviation
    return Math.sqrt(self.sample_variance)
  end

  def system_quality_number
    Math.sqrt(self.length) * self.mean / self.standard_deviation
  end

  def rank(val=nil,top=true)
    val ||= self.last.to_f
    min = self.min_by { |x| x.to_f }.to_f
    max = self.max_by { |x| x.to_f }.to_f
    range = max - min
    (top) ? (val-min) / range : (max-val) / range
  end
end
