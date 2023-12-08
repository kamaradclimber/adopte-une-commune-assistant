#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['PORT'] ||= '8111'

require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'irb'
require 'cgi'
require 'mixlib/shellout'

require_relative 'lib/adopte_une_commune/clochers'
require_relative 'lib/adopte_une_commune/osm'

SCRIPT_VERSION = Mixlib::ShellOut.new('git describe --tags --dirty').run_command.tap(&:error!).stdout
CONTROL_PORT = ENV.fetch('JOSM_CONTROL_PORT', 8112).to_i

def proxy_request(headers, uri, json_response: true)
  headers['Access-Control-Allow-Origin'] = 'https://maproulette.org'
  response_body = get_page(uri)

  if json_response
    JSON.parse(response_body)
  else
    response_body
  end
end

def kvize(hash, separator: '&')
  hash.map { |k, v| "#{k}=#{v}" }.join(separator)
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

get '/version' do
  uri = URI.parse("http://localhost:#{CONTROL_PORT}/version")
  r = proxy_request(headers, uri)
  r.merge({ proxied_by: 'adopte-une-commune-assistant' }).to_json
end

get '/load_and_zoom' do
  object_tags_hash = {
    'source:name': 'clochers.org'
  }

  # open relevant urls
  lon = params['left'].to_f + ((params['right'].to_f - params['left'].to_f) / 2)
  lat = params['bottom'].to_f + ((params['top'].to_f - params['bottom'].to_f) / 2)

  url = build_clochers_org_url(lat: lat, lon: lon)

  puts "Opening #{url}"
  Mixlib::ShellOut.new("xdg-open '#{url}'").run_command.error!

  uri = URI.parse(url)
  body = get_page(uri)
  churches = extract_churches(uri, body)
  case churches.size
  when 0
    puts '----------------------------------------------'
    puts '           WARNING: no church name detected   '
    puts '----------------------------------------------'
  when 1
    puts "> Church name is #{churches.first}"
    object_tags_hash['name'] = churches.first.name
    object_tags_hash['ref:clochers.org'] = churches.first.ref_clochers_org if churches.first.ref_clochers_org
    case churches.first.name
    when /chapelle/i
      object_tags_hash['building'] = 'chapel'
    when /eglise/i, /église/i
      object_tags_hash['building'] = 'church'
    end
  else
    puts 'WARNING: Several building detected, you have to pick the correct one manually'
    puts 'Names are:'
    churches.each do |n|
      puts "- #{n.name} (type: #{n.building_type}, ref #{n.ref_clochers_org})"
    end

    puts 'Fetching data from OSM'
    way_id = Regexp.last_match(1) if params['select'] =~ /^way(\d+)$/

    result = OSM.new.fetch_way(way_id)
    if result['elements'].one?
      tags = result['elements'].first['tags']
      by_type = churches.group_by(&:building_type)
      if by_type[tags['building']]&.one?
        church = by_type[tags['building']].first
        puts "There is a single building of type #{tags['building']} in this locality, guessing name is #{church.name}"
        object_tags_hash['name'] = church.name
        object_tags_hash['ref:clochers.org'] = church.ref_clochers_org if church.ref_clochers_org
      else
        puts "Found #{by_type[tags['building']]&.size || 0} building of type #{tags['building']}"
      end

    else
      puts "Found #{result['elements'].size} results corresponding to way #{way_id}, that's weird, would have expected exactly 1 result"
    end

  end

  # prepare the request to proxy
  query_string = request.env['rack.request.query_string']
  changeset_tags = CGI.escape(kvize({
                                      mechanical_edit: true,
                                      'script:name': 'adopte-une-commune-assistant',
                                      # 'script:version': SCRIPT_VERSION,
                                      'script:version': '0.2.1',
                                      'script:source': 'https://github.com/kamaradclimber/adopte-une-commune-assistant'
                                    }, separator: '|'))
  object_tags = CGI.escape(kvize(object_tags_hash, separator: '|'))

  query_string += "&changeset_tags=#{changeset_tags}"
  query_string += "&addtags=#{object_tags}"
  uri = URI.parse("http://localhost:#{CONTROL_PORT}/load_and_zoom?#{query_string}")
  proxy_request(headers, uri, json_response: false)
end
