require 'ekylibre-traccar/engine'

module EkylibreTraccar
  VENDOR = 'traccar'
  def self.root
    Pathname.new(File.dirname(__dir__))
  end
end
