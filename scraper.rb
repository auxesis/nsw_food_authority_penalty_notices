require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'pry'

@mappings = {
  'Trade name' => 'trading_name',
  'Name of convicted' => 'name_of_convicted',
  'Usual place of business' => 'place_of_business',
  'Council area' => 'council',
  'Address at which offence was committed' => 'offence_address',
  'Date of offence' => 'offence_date',
  'Nature and circumstances of offence' => 'description',
  'Date of decision' => 'decision_date',
  'Decision' => 'decision',
  'Court' => 'court',
  'Penalty' => 'penalty',
  'Decision details' => 'decision_details',
  'Prosecution brought by or for' => 'prosecution_brought_by',
  'Notes' => 'notes',
}

def scrub(text)
  text.gsub!(/[[:space:]]/, ' ') # convert all utf whitespace to simple space
  text.strip
end

def get(url)
  @agent ||= Mechanize.new
  @agent.get(url)
end

def extract_detail(page)
  details = {}

  rows = page.search('div.contentInfo table tbody tr').children.map {|e| e.text? ? nil : e }.compact

  rows.each_slice(2) do |key, value|
    k = scrub(key.text)
    case
    when @mappings[k]
      details.merge!({@mappings[k] => scrub(value.text)})
    when id = @mappings.keys.find {|matcher| k.match(matcher)}
      details.merge!({@mappings[id] => scrub(value.text)})
    else
      binding.pry
      raise "unknown field for '#{k}'"
    end
  end

  return details
end

def extract_notices(page)
  notices = []
  page.search('div.contentInfo div.table-container tbody tr').each do |el|
    notices << el
  end
  notices
end

def build_notice(el)
  notice = {
    'link' => "#{base}#{el.search('a').first['href']}"
  }
  page    = get(notice['link'])
  details = extract_detail(page)
  notice.merge!(details)
end

def geocode(notice)
  puts "Geocoding #{notice['offence_address']}"
  a = Geokit::Geocoders::GoogleGeocoder.geocode(notice['offence_address'])
  location = {
    'lat' => a.lat,
    'lng' => a.lng,
  }
  notice.merge!(location)
end

def base
  "http://www.foodauthority.nsw.gov.au"
end

def main
  page = get("#{base}/penalty-notices/default.aspx?template=results")

  notices = extract_notices(page)
  puts "Found #{notices.size} notices"
  notices.map! {|n| build_notice(n) }
  notices.reject! {|n| n.keys.size == 1 }
  notices.map! {|n| geocode(n) }

  # Serialise
  notices.each do |notice|
    ScraperWiki.save_sqlite(['link'], notice)
  end

  puts "Done"
end

main()
