# frozen_string_literals: true

class BooleanSuperposition
  attr_reader :val

  def initialize(value = false)
    @val = value
  end

  def val=(value)
    unless [:none, false, true, :either].include?(value)
      raise TypeError, "Value must be one of :none, false, true, or :either"
    end
    @val = value
  end

  def inspect
    case @val
    when :none
      "false (unset)"
    when false
      "false"
    when true
      "true"
    when :either
      "either"
    end
  end

  def +(value)
    case value
    when :none
      self
    when false
      return BooleanSuperposition.new(false) if @val == :none
      return self if @val == false
      return BooleanSuperposition.new(:either) if @val == true
      BooleanSuperposition.new(:either)
    when true
      return BooleanSuperposition.new(true) if @val == :none
      return BooleanSuperposition.new(:either) if @val == false
      return self if @val == true
      BooleanSuperposition.new(:either)
    when :either
      return self if @val == :either
      BooleanSuperposition.new(:either)
    end
  end

  def -(value)
    case value
    when :none
      self
    when false
      return BooleanSuperposition.new(:none) if @val == false
      return BooleanSuperPosition.new(true) if @val == :either
      self
    when true
      return BooleanSuperposition.new(:none) if @val == true
      return BooleanSuperposition.new(false) if @val == :either
      self
    when :either
      BooleanSuperposition.new(:none)
    end
  end
end
