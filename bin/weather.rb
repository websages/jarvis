###########################################################################
#  TITLE:         Weather plugin for Crunchy IRC bot
#   CREATED:    Brian Larkin, 3/5/2008
#   NOTES:       Written in Ruby - relies on the Google Weather API to get the data.
###########################################################################

require 'net/http'
require 'rexml/document'

include REXML

if ARGV.length < 1
  puts "Please provide a location to get weather for." 
  exit
elsif ARGV.length == 1
  city = ARGV[0]
elsif ARGV.length > 1
  ARGV.each { |arg| city = "#{city} #{arg}" }
end

pre = ['Hot and Wet','Arid and dusty','Frigid','Extremely windy','Polluted', 'Waterlogged']
post = [' with little chance of showers',' don\'t forget the earplugs',' remember to bring a parka',' don\'t forget to protect yourself from the elements',' try to combine trips and save', ' bring a raincoat and an umbrella'  ]

if city.index("smom") != nil
    idx = city.index("smom")  -1
    name = city[0..idx].capitalize
    puts "#{name}\'s Mom: #{pre[rand(pre.size)]}#{post[rand(post.size)]} " 
    exit
end

url = 'http://www.google.com/ig/api?weather=' + city

#trap any spaces and replace them with %20
url = url.gsub(' ','%20')

xml_data = Net::HTTP.get_response(URI.parse(url)).body
doc = Document.new xml_data

city = XPath.first( doc, "//forecast_information/city/attribute::data")
curr_temp = XPath.first( doc, "//current_conditions/temp_f/attribute::data").to_s  + 'ºF'
curr_hum = XPath.first( doc, "//current_conditions/humidity/attribute::data")
curr_win = XPath.first( doc, "//current_conditions/wind_condition/attribute::data")
curr_con = XPath.first( doc, "//current_conditions/condition/attribute::data")
today_low = XPath.first( doc, "//forecast_conditions/low/attribute::data")
today_high = XPath.first( doc, "//forecast_conditions/high/attribute::data")

if city == nil
  puts "No forecast for that location."
else
  puts "#{city}: #{curr_con} at #{curr_temp} with #{curr_hum} and #{curr_win}.  High today of #{today_high} and a low of #{today_low} "
end

