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
require_relative 'lib/adopte_une_commune/townhall_challenge3'
require_relative 'lib/adopte_une_commune/church_challenge'

SCRIPT_VERSION = Mixlib::ShellOut.new('git describe --tags --dirty').run_command.tap(&:error!).stdout
SCRIPT_VERSION = "0.4.0"
CONTROL_PORT = ENV.fetch('JOSM_CONTROL_PORT', 8112).to_i

if Mixlib::ShellOut.new('which fzf').run_command.error?
  puts 'You need to install fzf binary'
  exit(1)
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
  when /41214/
    uri = URI.parse(request.env['REQUEST_URI'].gsub(':8111/', ":#{CONTROL_PORT}/"))
    puts "proxy to #{uri}"
    proxy_request(headers, uri, json_response: false)

  else
    raise "Don't know how to treat this challenge. #{params['changeset_comment']}"
  end
end

