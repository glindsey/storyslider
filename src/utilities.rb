module Utilities
  def deep_init!(obj, *keys)
    hsh = obj
    hsh ||= {}
    keys.each do |key|
      hsh[:key] ||= {}
      hsh = hsh[:key]
    end
    hsh
  end
end
