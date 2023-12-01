#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'irb'
require 'cgi'
require 'mixlib/shellout'

require_relative 'lib/adopte_une_commune/clochers'

def proxy_request(uri, json_response: true)
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
  uri = URI.parse("http://localhost:#{ENV.fetch('JOSM_CONTROL_PORT', nil)}/version")
  r = proxy_request(uri)
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

  body = get_page(URI.parse(url))
  church_name = extract_church_name(body)
  if church_name
    puts "> Church name is #{church_name}"
    object_tags_hash['name'] = church_name
  else
    puts '----------------------------------------------'
    puts '           WARNING: no church name detected   '
    puts '----------------------------------------------'
  end

  # prepare the request to proxy
  query_string = request.env['rack.request.query_string']
  changeset_tags = CGI.escape(kvize({
                                      mechanical_edit: true,
                                      'script:name': 'adopte-une-commune-assistant',
                                      'script:version': '0.1.0',
                                      'script:source': 'https://github.com/kamaradclimber/adopte-une-commune-assistant'
                                    }, separator: '|'))
  object_tags = CGI.escape(kvize(object_tags_hash, separator: '|'))

  query_string += "&changeset_tags=#{changeset_tags}"
  query_string += "&addtags=#{object_tags}"
  uri = URI.parse("http://localhost:#{ENV.fetch('JOSM_CONTROL_PORT', nil)}/load_and_zoom?#{query_string}")
  proxy_request(uri, json_response: false)
end
