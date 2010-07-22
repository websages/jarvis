#!/usr/bin/env ruby
#
require 'net/http'
require 'rexml/document'
require 'uri'
require 'cgi'

include REXML

# Parse Proxy options
if ENV['http_proxy']
  proxy_host = ''
  proxy_port = ''
  # check to see if proxy_host is prefixed with http(s)://
  if ENV['http_proxy'].to_s.include?('://')
    proxy_host = ENV['http_proxy'].split('/')[-1].to_s
  else
    proxy_host = ENV['http_proxy']
  end
  
  # check to see if proxy_host is suffixed with a port
  if proxy_host =~ /:[0-9]+$/
    proxy_host, proxy_port = proxy_host.split(':')
    proxy_port = proxy_port.to_i
    proxy_host = proxy_host.to_s
  end

  unless proxy_port.is_a?(Integer)
    proxy_port = 80
  end
end


if ARGV[0] == nil
  symb = "cat"
else
  symb = ARGV[0]
end

unless symb 
  puts "Provide a symb code"
  exit 1
end


xml_data = ""

Net::HTTP::Proxy(proxy_host, proxy_port).start('www.google.com') do |http|
  xml_data = http.get("/ig/api?stock=#{symb}")
end

doc = Document.new xml_data.body
company= XPath.first(doc, "//company/attribute::data")
curr_price = XPath.first(doc, "//last/attribute::data").to_s
exchange = XPath.first(doc, "//exchange/attribute::data").to_s
change = XPath.first(doc, "//change/attribute::data").to_s
currency = XPath.first(doc, "//currency/attribute::data").to_s
market_cap = XPath.first(doc, "//market_cap//attribute::data").to_s
market_cap = market_cap.to_i * 1000  / 1000000.0
cap = market_cap
cap =  sprintf("%.2f", cap) + " B"

# Fix odd encoding on Dow Jones
exchange.gsub!(/nbsp\;/, " ")
exchange.gsub!(/&amp;/, "")



output= "#{symb.upcase} (#{company}) on the #{exchange} is currently #{change} #{currency} trading at #{curr_price}." 
if market_cap > 0 
  output <<  " Market Cap: #{cap} #{currency}" 
end
puts output
