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
    OverpassTurboResult.new(response.body, self)
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
  def initialize(object, nodes, client)
    @nodes = nodes
    @object = object
    @osm_type = nodes.one? ? :node : :way
    @client = client
  end

  def distance_in_km_from(th2)
    Distance.distance_in_km(lat, lon, th2.lat, th2.lon)
  end

  def lat
    @nodes.first['lat']
  end

  def lon
    @nodes.first['lon']
  end

  def _tags
    @object['tags']
  end

  def single_point?
    @nodes.one?
  end

  def name
    _tags['name']
  end

  def josm_id
    "#{@osm_type}#{id}"
  end

  def id
    @object['id']
  end

  def bounding_objects
    @bounding_objects ||= @client.query_bounding_objects(self)
  end

  # this should be used when name is not filled
  def guess_name(admin_type)
    candidate = bounding_objects
                .data['elements']
                .select { |el| el['type'] == 'relation' }
                .find { |el| el['tags']['admin_type:FR'] == admin_type }
    return unless candidate

    city_name = candidate['tags']['name']

    name = 'Mairie '
    name += case city_name.downcase
            when /ˆ[aeiouyé]/
              "d'" + city_name
            when /le /
              'du ' + city_name[3..]
            when /les /
              'des ' + city_name[4..]
            else
              'de ' + city_name
            end
    name
  end

  def commune_centre?
    bounding_objects
      .data['elements']
      .select { |el| el['type'] == 'relation' }
      .any? { |el| el['tags']['admin_type:FR'] == 'commune centre' }
  end

  def commune_associee?
    bounding_objects
      .data['elements']
      .select { |el| el['type'] == 'relation' }
      .any? { |el| el['tags']['admin_type:FR'] == 'commune associée' }
  end

  def commune_deleguee?
    bounding_objects
      .data['elements']
      .select { |el| el['type'] == 'relation' }
      .any? { |el| el['tags']['admin_type:FR'] == 'commune déléguée' }
  end

  def self.build_from(way, nodes, client)
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
    @townhalls ||= begin
      nodes = @data['elements'].select { |el| el['type'] == 'node' }.to_h do |n|
        [n['id'], { 'lat' => n['lat'], 'lon' => n['lon'] }]
      end
      way_ths = @data['elements'].select { |el| el['type'] == 'way' }.map do |way|
        Townhall.build_from(way, nodes, @client)
      end
      node_ths = @data['elements'].select { |el| el['type'] == 'node' }.select { |el| el['tags']&.fetch('amenity') == 'townhall' }.map do |node|
        Townhall.new(node, [node], @client)
      end
      way_ths + node_ths
    end
  end

  def boundaries
    all_nodes = @data['elements'].select { |el| el['type'] == 'node' }

    lats = all_nodes.map { |n| n['lat'] }.sort
    lons = all_nodes.map { |n| n['lon'] }.sort
    delta = 0.001

    {
      'right' => lons.max + delta,
      'left' => lons.min - delta,
      'bottom' => lats.min - delta,
      'top' => lats.max + delta
    }
  end
end

class GeoApiGouvClient
  def mairies(department)
    @mairies ||= {}
    @mairies[department] ||= _mairies(department)
  end

  def _mairies(department)
    uri = URI.parse("https://geo.api.gouv.fr/departements/#{department}/communes?geometry=mairie&format=geojson")
    request = Net::HTTP::Get.new(uri)
    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    raise "Invalid code when querying townhall list, code: #{response.code}" unless response.code.to_i == 200

    JSON.parse(response.body)['features']
  end

  # @returns [Float]
  def distance_to_main_townhall(townhall)
    # this works by finding all townhalls from the department (from a list that contains only "official" townhalls, i.e not mairie de commune déléguées)
    insee_data = Insee.new.get_insee_data(lat: townhall.lat, lon: townhall.lon)
    all_townhalls = mairies(insee_data[:department])
    closest = all_townhalls.min_by do |townhall_geodata|
      coords = townhall_geodata['geometry']['coordinates']
      Distance.distance_in_km(townhall.lat, townhall.lon, coords[1], coords[0])
    end
    coords = closest['geometry']['coordinates']
    d = Distance.distance_in_km(townhall.lat, townhall.lon, coords[1], coords[0]).round(3)
    d = d.round(1) if d > 1 # no point in showing too much precision
    puts "Closest townhall is '#{closest['properties']['nom']}', #{d}km away"
    d
  end
end

module Distance
  def self.distance_in_km(lat1, lon1, lat2, lon2)
    earth_radius = 6371
    p = Math::PI / 180
    a = 0.5 - (Math.cos((lat2 - lat1) * p) / 2) + (Math.cos(lat1 * p) * Math.cos(lat2 * p) * (1 - Math.cos((lon2 - lon1) * p)) / 2)
    2 * earth_radius * Math.asin(Math.sqrt(a))
  end
end

class Patchset
  def initialize(params, changeset_tags)
    @params = params
    @tags = {}
    @select = []
    @changeset_tags = changeset_tags
  end

  attr_accessor :debug_info

  attr_reader :params, :tags, :select

  def to_request
    object_tags = kvize(tags, separator: '|')
    @params['addtags'] = object_tags if object_tags.size.positive?
    @params['select'] = select.join(',') if select.any?
    @params['changeset_tags'] = @changeset_tags
    @params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
  end

  def kvize(hash, separator: '&')
    hash.map { |k, v| "#{k}=#{v}" }.join(separator)
  end
end
