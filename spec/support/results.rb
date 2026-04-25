# frozen_string_literal: true

class Results < Array
  def self.instance
    @instance ||= new
  end

  def counter
    @counter ||= 0
  end

  def increment
    @counter += 1
  end

  def clear
    @counter = 0
    super
  end
end
