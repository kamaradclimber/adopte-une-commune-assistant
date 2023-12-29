require_relative 'helpers'

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
  xdgopen(url)

  geo_api_gouv_client = GeoApiGouvClient.new

  object = turbo_client.fetch_data(overpass_query)

  puts "--------------------\n\n"
  ths = object.townhalls
  puts "There are #{ths.size} townhalls in this view"

  proxied_params = params.dup
  proxied_params.merge!(object.boundaries)
  changeset_tags = kvize({
                           mechanical_edit: true,
                           source: 'Openstreetmap bounding objects',
                           'script:name': 'adopte-une-commune-assistant',
                           'script:version': SCRIPT_VERSION,
                           'script:source': 'https://github.com/kamaradclimber/adopte-une-commune-assistant'
                         }, separator: '|')
  patchsets = []

  solved = false
  if object.townhalls.size == 2
    single_point_townhall = object.townhalls.find(&:single_point?)
    others = object.townhalls.reject(&:single_point?)
    if single_point_townhall && others.any? && single_point_townhall.distance_in_km_from(others.first) < 0.100
      puts 'Known case: one way and one node representing the same building'
      puts 'You should delete the point version'
      solved = true
      patchset = Patchset.new(proxied_params.dup, changeset_tags)
      patchsets << patchset
      patchset.select << single_point_townhall.josm_id
    end
  end
  unless solved
    if ths.all?(&:commune_deleguee?) || ths.all? { |th| th.commune_associee? || th.commune_centre? }
      puts "let's find the main mairie"
      min_dist = ths.map { |th| geo_api_gouv_client.distance_to_main_townhall(th) }.min
      # we assume the main townhall to be at most 50m away from "official" townhall location
      threshold = [min_dist, 0.05].min
      ths.each do |th|
        name = th.name
        patchset = Patchset.new(proxied_params.dup, changeset_tags)
        patchset.restrict_boundaries!(th)
        if geo_api_gouv_client.distance_to_main_townhall(th) <= threshold
          old_name = th.guess_name('commune déléguée')
          old_name ||= th.guess_name('commune centre')
          name ||= th.guess_name('commune nouvelle')
          name ||= th.guess_name('commune centre')
          puts "#{name || '""'} is the main townhall (old name: #{old_name})"
          patchset.debug_info = "Adding 'mairie principale' tag to #{name || '""'}"
          patchset.tags['townhall:type'] = 'Mairie principale'
          solved = true
        else
          name ||= th.guess_name('commune déléguée')
          name ||= th.guess_name('commune associée')
          puts "#{name || '""'} is a delegated townhall"
          tag = if th.commune_deleguee?
                  "Mairie de commune déléguée"
                elsif th.commune_associee?
                  "Mairie de commune associée"
                else
                  raise "No tag for #{th.inspect}"
                end
          patchset.debug_info = "Adding '#{tag}' tag to #{name || '""'}"
          patchset.tags['townhall:type'] = tag
        end
        patchsets << patchset
        patchset.select << th.josm_id
        patchset.tags['name'] = name unless th.name
      end
    end

    unless solved
      ths.each do |th|
        puts "- #{th.name || 'no name'}"
      end
      puts 'what should we do with those?'
    end
    puts "\n\n--------------------"
    patchset = Patchset.new(proxied_params.dup, changeset_tags)
    patchset.debug_info = 'Adding general tags to the changeset'
    patchsets << patchset
    ths.each do |th|
      patchset.select << th.josm_id
    end
  end

  patchsets.each_with_index do |p, index|
    query_string = p.to_request
    uri = URI.parse("http://localhost:#{CONTROL_PORT}/load_and_zoom?#{query_string}")
    if patchsets.size > 1
      print "Creating patchset #{index + 1}  "
      print ": #{p.debug_info}" if p.debug_info
      puts ''
    end
    proxy_request(headers, uri, json_response: false)
  end
  {}.to_json
end

