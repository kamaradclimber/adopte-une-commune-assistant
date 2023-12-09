# frozen_string_literal: true

require 'json'
require 'ruby-cheerio'
require 'net/http'

class Church
  attr_accessor :name, :ref_clochers_org, :building_type
end

def enrich_building(church)
  church.building_type = case church.name
                         when /eglise/i, /église/i
                           'church'
                         when /chapelle/i
                           'chapel'
                         end
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

# @returns Array<Church> detected names
def extract_churches(uri, body)
  # TODO(kamaradlimber): encoding detection does not work and always see "UTF8" which is
  # wrong when looking at the source
  # j = RubyCheerio.new(body)
  # content_type = j.find('meta:first').first&.prop('meta', 'content') || ''
  # encoding = Regexp.last_match(1) if content_type =~ /charset=([a-z0-9-]+)/
  # encoding ||= 'utf-8'
  encoding = 'iso-8859-1'
  puts "Detected page encoding is #{encoding}"
  j = RubyCheerio.new(body.force_encoding(encoding).encode('utf-8'))
  churches = []

  others = j.find('center > table:first > tr:last > td > div > font > a').map(&:text)
  if others.any?
    church = Church.new
    church.name = clean(j.find('center > table:first > tr:last > td > div > font > strong').map(&:text).first)
    church.ref_clochers_org = Regexp.last_match(1) if church && uri.path =~ %r{/accueil_([^/]+).htm}
    churches << church
    others.each do |text|
      churches << Church.new.tap do |c|
        c.name = clean(text)
        enrich_building(church)
      end
    end
  else
    names = j.find('center > table:first > tr:last').map(&:text)
    if names.any? # there is a single building on that page
      church = Church.new
      church.name = clean(names.first)
      enrich_building(church)
      church.ref_clochers_org = Regexp.last_match(1) if church && uri.path =~ %r{/accueil_([^/]+).htm}
      churches << church
    else
      # there are many buildings on that page
      items = j.find('table:last > tr > td > font > a')
      items.each do |item|
        c = Church.new
        c.ref_clochers_org = Regexp.last_match(1) if item.prop('a', 'href') =~ %r{accueil_([^/]+).htm}
        c.name = clean(item.text)
        enrich_building(c)
        churches << c
      end
    end
  end
  puts 'Could really not find any church description on the page' if churches.empty?
  churches
end

def clean(text)
  text
    .gsub("\n", ' ')
    .gsub('  ', ' ') # weird characters?
    .gsub(/ +/, ' ')
    .gsub(/ \(.+\)/, '') # remove sub locality name
    .gsub(/, .+/, '') # remove precision like "désaffectée"
    .strip
    .chomp(' -') # end of first name when multiple buildings
end
