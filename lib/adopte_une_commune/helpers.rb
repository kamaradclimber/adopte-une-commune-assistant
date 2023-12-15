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

class OverpassTurboClient
  def get_map_url(query)
    "https://overpass-turbo.eu/map.html?Q=#{CGI.escape(query)}"
  end

  def fetch_data(query)
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
    OverpassTurboResult.new(response.body)
  end
end

class Townhall
  def initialize(way, nodes)
    @nodes = nodes
    @way = way
  end

  def name
    name_tags = @way.find("[k='name']")
    case name_tags.size
    when 1
      name_tags.first.prop('tag', 'v')
    when 0
      raise 'No name for this object?'
    else
      raise 'There are several name tags on this object?'
    end
  end

  def self.build_from(way, nodes)
    way_nodes = way.find('nd').map do |nd| # resolve nodes
      ref = nd.prop('nd', 'ref')
      n = nodes[ref]
      puts "WARNING: cant find reference to #{ref}, something is very wrong" unless n
      n
    end
    Townhall.new(way, way_nodes)
  end
end

class OverpassTurboResult
  def initialize(body)
    @body = body
    @j = RubyCheerio.new(@body)
  end

  def townhall_count
    @j.find("[v='townhall']").size
  end

  def townhalls
    nodes = @j.find('node').to_h do |n|
      [n.prop('node', 'id'), { lat: n.prop('node', 'lat').to_f, lon: n.prop('node', 'lon').to_f }]
    end
    @j.find('way').map do |way|
      Townhall.build_from(way, nodes)
    end
  end

  def boundaries
    all_nodes = @j.find('node')

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
