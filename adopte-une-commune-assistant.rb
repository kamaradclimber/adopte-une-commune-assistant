#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'irb'
require 'cgi'

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

get '/version' do
  uri = URI.parse("http://localhost:#{ENV['JOSM_CONTROL_PORT']}/version")
  r = proxy_request(uri)
  r.merge({ "proxied_by": 'adopte-une-commune-assistant' }).to_json
end

get '/load_and_zoom' do
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
  proxy_request(uri, response_json: false)
end
