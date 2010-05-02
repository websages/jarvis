###########################################################################
#  TITLE:         Insult plugin for Crunchy IRC bot
#   CREATED:    Brian Larkin, 3/7/2008
#   NOTES:       Written in Ruby - does a simple screen scrape to get an insult.
###########################################################################

require 'net/http'

begin
  if ARGV.length == 1
    target = "#{ARGV[0]}: ".capitalize
  end

  url = "http://www.randominsults.net/"
  data = Net::HTTP.get_response(URI.parse(url)).body

  parsed = data.gsub!(/.*<td bordercolor="#FFFFFF"><font face="Verdana" size="4"><strong><i>/m,'')
  parsed = parsed.gsub!(/<\/i><\/strong><\/font>&nbsp;<\/td>.*/m,'')

  if parsed.length > 0 && parsed.length < 100
  puts "#{target}#{parsed}"
  else
    puts "Yo Momma"
  end
rescue
  puts "Yo Momma"
end
