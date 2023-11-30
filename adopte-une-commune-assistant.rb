#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'irb'
require 'cgi'
require 'mixlib/shellout'

def proxy_request(uri, json_response: true)
  request = Net::HTTP::Get.new(uri)
  req_options = {
    use_ssl: uri.scheme == 'https'
  }

  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(request)
  end

  raise "Code was #{response.code}" unless response.code.to_i == 200

  if json_response
    JSON.parse(response.body)
  else
    response.body
  end
end

def kvize(hash, separator: '&')
  hash.map { |k, v| "#{k}=#{v}" }.join(separator)
end

def build_clochers_org_url(lat:, lon:)
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
  "https://clochers.org/Fichiers_HTML/Accueil/Accueil_clochers/#{department}/accueil_#{insee_code}.htm"
end

get '/version' do
  uri = URI.parse("http://localhost:#{ENV['JOSM_CONTROL_PORT']}/version")
  r = proxy_request(uri)
  r.merge({ "proxied_by": 'adopte-une-commune-assistant' }).to_json
end

get '/load_and_zoom' do
  # open relevant urls
  lon = params['left'].to_f + (params['right'].to_f - params['left'].to_f) / 2
  lat = params['bottom'].to_f + (params['top'].to_f - params['bottom'].to_f) / 2

  redirect_url = build_clochers_org_url(lat: lat, lon: lon)

  puts "Opening #{redirect_url}"
  Mixlib::ShellOut.new("xdg-open '#{redirect_url}'").run_command.error!

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
