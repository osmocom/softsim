#!/usr/bin/env ruby
require 'client'
require 'socket'

class DemoClient < Client
  def initialize(io)
    super(io)
  end
end

# demo application, using TCP socket
io = TCPSocket.open("localhost",1234)
client = DemoClient.new(io)
client.start
client.connect
atr = client.atr
puts atr ? "ATR : #{atr.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get ATR"
client.disconnect