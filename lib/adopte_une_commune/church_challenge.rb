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
                                      'script:version': SCRIPT_VERSION,
                                      'script:source': 'https://github.com/kamaradclimber/adopte-une-commune-assistant'
                                    }, separator: '|'))
  object_tags = CGI.escape(kvize(object_tags_hash, separator: '|'))

  query_string += "&changeset_tags=#{changeset_tags}"
  query_string += "&addtags=#{object_tags}"
  uri = URI.parse("http://localhost:#{CONTROL_PORT}/load_and_zoom?#{query_string}")
  proxy_request(headers, uri, json_response: false)
end
