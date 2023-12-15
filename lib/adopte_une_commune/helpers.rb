# frozen_string_literal: true

require 'json'
require 'net/http'
require 'ruby-cheerio'

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

class OverpassTurbo
  def get_url(query)
    "https://overpass-turbo.eu/map.html?Q=#{CGI.escape(query)}"
  end

  def get_boundaries(query)
    uri = URI.parse('https://overpass-api.de/api/interpreter')
    request = Net::HTTP::Post.new(uri)
    request.set_form_data({ 'data' => query })
    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    unless response.code.to_i == 200
      puts response.body
      raise "Invalid code when querying overpass turbo. Code was #{response.code}"
    end
    j = RubyCheerio.new(response.body)

    all_nodes = j.find('node')

    lats = all_nodes.map { |n| n.prop('node', 'lat').to_f }.sort
    lons = all_nodes.map { |n| n.prop('node', 'lon').to_f }.sort

    {
      'right' => lons.max,
      'left' => lons.min,
      'bottom' => lats.min,
      'top' => lats.max
    }
  end
end
