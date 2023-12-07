# frozen_string_literal: true

require 'uri'
require 'net/http'

class OSM
  def fetch_way(id)
    uri = URI.parse("https://overpass-api.de/api/interpreter?data=%5Bout%3Ajson%5D%5Btimeout%3A25%5D%3Barea%283602202162%29%2D%3E%2EsearchArea%3Bway%28#{id}%29%28area%2EsearchArea%29%3Bout%20geom%3B%0A")
    JSON.parse(get_page(uri))
  end

  def get_page(uri)
    request = Net::HTTP::Get.new(uri)
    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    raise "Code was #{response.code}" unless response.code.to_i == 200

    response.body
  end
end
