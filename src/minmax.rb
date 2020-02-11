# frozen_string_literals: true

class MinMax
  attr_accessor :min, :max

  def initialize(min_value = 0, max_value = 0)
    @min = min_value
    @max = max_value
  end

  def +(value)
    new_min = (min < value) ? min : value
    new_max = (max > value) ? max : value
    return MinMax.new(new_min, new_max)
  end

  def inspect
    "#{@min}..#{@max}"
  end
end
