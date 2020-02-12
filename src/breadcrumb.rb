# frozen_string_literals: true

class Breadcrumb
  attr_reader :id, :vars

  def initialize(id, vars = {})
    @id = id
    @vars = vars
  end
end
