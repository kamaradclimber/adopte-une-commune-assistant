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

  def query_bounding_objects(townhall)
    geom = [townhall.lat * 0.999, townhall.lon * 0.999, townhall.lat * 1.001, townhall.lon * 1.001].map(&:to_s)
    data = <<~DATA.gsub(/\n/, '')
      [timeout:10]
      [out:json];
      is_in(#{townhall.lat},#{townhall.lon})->.a;
      way(pivot.a);
      out tags bb;
      out ids geom(#{geom.join(',')});
      relation(pivot.a);
      out tags bb;
    DATA
    fetch_data(data)
  end
end

class Townhall
  def initialize(way, nodes, client)
    @nodes = nodes
    @way = way
    @osm_type = :way
    @client = client
  end

  def lat
    @nodes.first[:lat]
  end

  def lon
    @nodes.first[:lon]
  end

  def _tags
    @way['tags']
  end

  def name
    name_tag = _tags['name']
    raise 'No name for this object?' unless name_tag

    name_tag
  end

  def josm_id
    "#{@osm_type}#{id}"
  end

  def id
    @way['id']
  end

  def bounding_objects
    @bounding_objects ||= client.query_bounding_objects(self)
  end

  def commune_deleguee?
    bounding_objects
      .data['elements']
      .select { |el| el['type'] == 'relation' }
      .any? { |el| el['tags']['admin_type:FR'] == 'commune déléguée' }
  end

  def self.build_from(way, nodes)
    way_nodes = way['nodes'].map do |ref| # resolve nodes
      n = nodes[ref]
      puts "WARNING: cant find reference to #{ref}, something is very wrong" unless n
      n
    end
    Townhall.new(way, way_nodes, client)
  end
end

class OverpassTurboResult
  def initialize(body, client)
    @client = client
    @data = JSON.parse(body)
  end
  attr_reader :data

  def townhall_count
    @data['elements'].count { |el| el['tags']&.fetch('amenity') == 'townhall' }
  end

  def townhalls
    nodes = @data['elements'].select { |el| el['type'] == 'node' }.to_h do |n|
      [n['id'], { lat: n['lat'], lon: n['lon'] }]
    end
    @data['elements'].select { |el| el['type'] == 'way' }.map do |way|
      Townhall.build_from(way, nodes, client)
    end
  end

  def boundaries
    all_nodes = @data['elements'].select { |el| el['type'] == 'node' }

    lats = all_nodes.map { |n| n['lat'] }.sort
    lons = all_nodes.map { |n| n['lon'] }.sort

    {
      'right' => lons.max,
      'left' => lons.min,
      'bottom' => lats.min,
      'top' => lats.max
    }
  end
end
