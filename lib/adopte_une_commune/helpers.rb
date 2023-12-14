# frozen_string_literal: true

require 'json'
require 'net/http'

class Insee
  def get_insee_data(lat:, lon:)
    # This method is doing an emulation of "https://bano.openstreetmap.fr/pifometre/clochers.html?lat=#{lat}&lon=#{lon}"
    raise ArgumentError("lat #{lat} must be within (-90..90)") unless (-90..90).include?(lat.round(0))
    raise ArgumentError("lon #{lat} must be within (-180..180)") unless (-180..180).include?(lon.round(0))

    uri = URI.parse("https://bano.openstreetmap.fr/pifometre/insee_from_coords.py?lat=#{lat}&lon=#{lon}")
    request = Net::HTTP::Get.new(uri)
    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    raise "Invalid code when querying insee code: #{response.code}" unless response.code.to_i == 200

    insee_code = JSON.parse(response.body)[0][0]
    department = if insee_code =~ /^97/
                   insee_code[0...3]
                 else
                   insee_code[0...2]
                 end

    { insee_code: insee_code, department: department }
  end
end
