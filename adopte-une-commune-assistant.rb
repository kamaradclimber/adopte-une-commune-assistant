#!/usr/bin/env ruby

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


get '/load_and_zoom' do
  # open relevant urls
  lon = params['left'].to_f + (params['right'].to_f - params['left'].to_f) / 2
  lat = params['bottom'].to_f + (params['top'].to_f - params['bottom'].to_f) / 2

  url = build_clochers_org_url(lat: lat, lon: lon)

  puts "Opening #{url}"
  Mixlib::ShellOut.new("xdg-open '#{url}'").run_command.error!
  extract_eglise_name(URI.parse(url))

  # prepare the request to proxy
  query_string = request.env['rack.request.query_string']
  changeset_tags = CGI.escape(kvize({
                                      mechanical_edit: true,
                                      'script:name': 'adopte-une-commune-assistant',
                                      'script:version': '0.1.0',
                                      'script:source': 'https://github.com/kamaradclimber/adopte-une-commune-assistant'
                                    }, separator: '|'))
  query_string += "&changeset_tags=#{changeset_tags}"
  object_tags = CGI.escape(kvize({
                                   'source:name': 'clochers.org'
                                 }))
  query_string += "&addtags=#{object_tags}"
  uri = URI.parse("http://localhost:#{ENV['JOSM_CONTROL_PORT']}/load_and_zoom?#{query_string}")
  proxy_request(uri, json_response: false)
end
