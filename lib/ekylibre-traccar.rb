require 'ekylibre-traccar/engine'

module EkylibreTraccar
  def self.root
    Pathname.new(File.dirname(__dir__))
  end
end
