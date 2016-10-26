require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'pry'

# Set an API key if provided
Geokit::Geocoders::GoogleGeocoder.api_key = ENV['MORPH_GOOGLE_API_KEY'] if ENV['MORPH_GOOGLE_API_KEY']

@mappings = {
  'Penalty notice number' => 'offence_id',
  'Trade name of party served' => 'trading_name',
  'Address(where offence occurred)' => 'address',
  'Council(where offence occurred)' => 'council',
  'Date of alleged offence' => 'offence_date',
  'Offence code' => 'offence_code',
  'Nature & circumstances of alleged offence' => 'offence_nature',
  'Amount of penalty' => 'penalty_amount',
  'Name of party served' => 'party_served',
  'Date penalty notice served' => 'date_served',
  'Issued by' => 'issued_by',
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
    notices << { 'link' => "#{base}#{el.search('a').first['href']}" }
  end
  notices
end

def build_notice(notice)
  page    = get(notice['link'])
  details = extract_detail(page)
  puts "Extracting #{details['address']}"
  notice.merge!(details)
end

def geocode(notice)
  @addresses ||= {}

  address = notice['address']

  if @addresses[address]
    puts "Geocoding [cache hit] #{address}"
    location = @addresses[address]
  else
    puts "Geocoding #{address}"
    a = Geokit::Geocoders::GoogleGeocoder.geocode(address)
    location = {
      'lat' => a.lat,
      'lng' => a.lng,
    }

    @addresses[address] = location
  end

  notice.merge!(location)
end

def base
  "http://www.foodauthority.nsw.gov.au/penalty-notices/default.aspx"
end

def existing_record_ids
  return @cached if @cached
  @cached = ScraperWiki.select('link from data').map {|r| r['link']}
rescue SqliteMagic::NoSuchTable
  []
end

def main
  page = get("#{base}?template=results")

  notices = extract_notices(page)
  puts "### Found #{notices.size} notices"
  new_notices = notices.select {|r| !existing_record_ids.include?(r['link']) }
  puts "### There are #{new_notices.size} new notices"

  new_notices.map! {|n| build_notice(n) }
  new_notices.reject! {|n| n.keys.size == 1 }
  new_notices.map! {|n| geocode(n) }

  # Serialise
  ScraperWiki.save_sqlite(['link'], new_notices)

  puts "Done"
end

main()
