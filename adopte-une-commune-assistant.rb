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
require_relative 'lib/adopte_une_commune/helpers'

SCRIPT_VERSION = Mixlib::ShellOut.new('git describe --tags --dirty').run_command.tap(&:error!).stdout
CONTROL_PORT = ENV.fetch('JOSM_CONTROL_PORT', 8112).to_i

if Mixlib::ShellOut.new('which fzf').run_command.error?
  puts 'You need to install fzf binary'
  exit(1)
end

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
  case params['changeset_comment']
  when /place_of_worship.+41666/i
    treat_church_challenge(params, headers)
  when /adopteunecommune.+townhall.+42138/i
    treat_town_hall_challenge3(params, headers)
  else
    raise "Don't know how to treat this challenge. #{params['changeset_comment']}"
  end
end

def treat_town_hall_challenge3(params, _headers)
  lon = params['left'].to_f + ((params['right'].to_f - params['left'].to_f) / 2)
  lat = params['bottom'].to_f + ((params['top'].to_f - params['bottom'].to_f) / 2)
  insee_code = Insee.new.get_insee_data(lat: lat, lon: lon)[:insee_code]

  overpass_query = <<~QUERY
    [out:json];
    area["ref:INSEE"=#{insee_code}];
      (nwr(area)[amenity=townhall];);
    (._;>;);
    out meta;
  QUERY
  turbo_client = OverpassTurboClient.new

  url = turbo_client.get_map_url(overpass_query)
  puts "Opening #{url}"
  Mixlib::ShellOut.new("xdg-open '#{url}'").run_command.error!

  object = turbo_client.fetch_data(overpass_query)

  puts "--------------------\n\n"
  puts "There are #{object.townhall_count} townhalls in this view"

  ths = object.townhalls
  puts "There are #{ths.size} non-point townhalls in this view:"
  ths.each do |th|
    puts "- #{th.name} #{th.commune_deleguee? ? 'is' : 'is not'} a 'commune déléguée'"
  end
  puts "\n\n--------------------"

  select = ths.map(&:josm_id).join(',')
  proxied_params = params.dup
  proxied_params.merge!(object.boundaries)
  changeset_tags = kvize({
                           mechanical_edit: true,
                           'script:name': 'adopte-une-commune-assistant',
                           # 'script:version': SCRIPT_VERSION,
                           'script:version': '0.2.1',
                           'script:source': 'https://github.com/kamaradclimber/adopte-une-commune-assistant'
                         }, separator: '|')

  proxied_params['select'] = select
  proxied_params['changeset_tags'] = changeset_tags
  query_string = proxied_params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
  uri = URI.parse("http://localhost:#{CONTROL_PORT}/load_and_zoom?#{query_string}")
  proxy_request(headers, uri, json_response: false)
end

def treat_church_challenge(params, headers)
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
  church = nil
  case churches.size
  when 0
    puts '----------------------------------------------'
    puts '           WARNING: no church name detected   '
    puts '----------------------------------------------'
  when 1
    puts "> Church name is #{churches.first.name}"
    church = churches.first
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
      by_type = if tags['building'] == 'yes'
                  # when we don't know the type of building, select all of them
                  { 'yes' => churches }
                else
                  churches.group_by(&:building_type)
                end
      if by_type[tags['building']]&.one?
        church = by_type[tags['building']].first
        puts "There is a single building of type #{tags['building']} in this locality, guessing name is #{church.name}"
      else
        puts "Found #{by_type[tags['building']]&.size || 0} building of type #{tags['building']}"
      end

      # case with wikidata data, will allow to confirm name
      if tags.key?('wikidata')
        wikidata_url = "https://www.wikidata.org/wiki/#{tags['wikidata']}"
        Mixlib::ShellOut.new("xdg-open '#{wikidata_url}'").run_command.error!
      end

    else
      puts "Found #{result['elements'].size} results corresponding to way #{way_id}, that's weird, would have expected exactly 1 result"
      raise AssertionError, 'Impossible situation'
    end
  end

  if church.nil? && churches.any?
    query_string = request.env['rack.request.query_string']
    uri = URI.parse("http://localhost:#{CONTROL_PORT}/load_and_zoom?#{query_string}")
    proxy_request(headers, uri, json_response: false)
    puts "Please select amongst the #{churches.size} possibilities"
    selected_name = `echo -n -e "#{churches.map(&:name).join("\n")}" | fzf`.strip
    puts "Selected '#{selected_name}'"
    church = churches.find { |c| c.name == selected_name }
  end

  if church.nil?
    puts 'We could really not find any result'
  else
    object_tags_hash['name'] = church.name
    object_tags_hash['ref:clochers.org'] = church.ref_clochers_org if church.ref_clochers_org
    case church.name
    when /chapelle/i
      object_tags_hash['building'] = 'chapel'
    when /eglise/i, /église/i
      object_tags_hash['building'] = 'church'
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
