# frozen_string_literal: true

require 'json'
require 'ruby-cheerio'
require 'net/http'

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

# @returns Array<String> detected names
def extract_church_names(body)
  # TODO(kamaradlimber): encoding detection does not work and always see "UTF8" which is
  # wrong when looking at the source
  # j = RubyCheerio.new(body)
  # content_type = j.find('meta:first').first&.prop('meta', 'content') || ''
  # encoding = Regexp.last_match(1) if content_type =~ /charset=([a-z0-9-]+)/
  # encoding ||= 'utf-8'
  encoding = 'iso-8859-1'
  puts "Detected page encoding is #{encoding}"
  j = RubyCheerio.new(body.force_encoding(encoding).encode('utf-8'))

  others = j.find('center > table:first > tr:last > td > div > font > a').map(&:text)
  potential_names = if others.any?
                      j.find('center > table:first > tr:last > td > div > font > strong').map(&:text)
                    else
                      j.find('center > table:first > tr:last').map(&:text)
                    end
  (potential_names + others).map { |text| clean(text) }
end

def clean(text)
  text
    .gsub("\n", ' ')
    .gsub('  ', ' ') # weird characters?
    .gsub(/ +/, ' ')
    .strip
    .chomp(' -') # end of first name when multiple buildings
end
