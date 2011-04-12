#!/usr/bin/env ruby
# This programm will create a client which can be used to test servers
require 'client'

# wich IO to use
client_io = :tcp
# the IO itself
io = nil
# create IO
case client_io
when :tcp
  require 'socket'
  host = "localhost"
  port = 1337
  io = TCPSocket.open(host,port)
when :bt
  require 'bluetooth_client'
  #sudo gem install serialport (http://rubygems.org/gems/serialport)
  require 'rubygems'
  require 'serialport'
=begin
to monitor bluetooth traffic
sudo aptitude install bluez-hcidump
sudo hcidump -x -i hci0 rfcomm
=end
  bt = BluetoothClient.new
  # using SerialPort because reading the File does not work (have to find right stty options)
  io = SerialPort.new(bt.connect)
else
  raise "please defined which client to use"
end

client = Client.new(io)
client.start
client.connect
atr = client.atr
puts atr ? "ATR : #{atr.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get ATR"
# select MF
apdu_req = [0xA0,0xA4,0x00,0x00,0x02,0x3F,0x00]
puts "APDU request : #{apdu_req.collect{|x| x.to_s(16).rjust(2,'0')}*' '}"
apdu_resp = client.apdu(apdu_req)
puts apdu_resp ? "APDU response : #{apdu_resp.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get APDU response"
client.disconnect

# close client_io
case client_io
when :tcp
  io.close
when :bt
  io.close
  bt.close
end