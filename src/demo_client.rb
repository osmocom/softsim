#!/usr/bin/env ruby
# encoding: UTF-8
=begin
This file is part of softSIM.

softSIM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

softSIM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with sofSIM.  If not, see <http://www.gnu.org/licenses/>.

Copyright (C) 2011 Kevin "tsaitgaist" Redon kevredon@mail.tsaitgaist.info
=end
# this programm will create a client which can be used to test servers
require './sap/client.rb'
require './lib/apdu.rb'
require './info_client.rb'
require './copy_client.rb'

#=============
#== default ==
#=============

# client use (demo,info,copy)
@type = "demo"
# which IO to use (tcp,unix,bt)
@socket = "tcp"
# tcp port
@port = 1337
# tcp host
@host = "localhost"
# unix socket
@unix = "/tmp/sap.socket"
# file were to save the copy
@file = "sim.xml"
# bluetooth rfcomm serial port
@bt = nil
# the verbosity (from common)
$verbosity = 0

#=============
#== methods ==
#=============

include APDU

# tell APDU methods how to send
def transmit_apdu(apdu)
  return @client.apdu(apdu)
end

# show help
def print_help
  puts "demo_client.rb [options]"
  puts ""
  puts "demonstration SAP client connecting to an indicated SAP server"
  puts "it executes some common commands"
  puts ""
  puts "options :"
  puts " --help,-h\t\tprint this help"
  puts " --type,-t client\tclient type: demo,info,copy (default #{@type})"
  puts " --socket,-s type\tsocket type: tcp,unix,bt (default #{@socket})"
  puts " --tcp,-p port\t\ttcp port (default #{@port})"
  puts " --host,-l host\t\ttcp host (default #{@host})"
  puts " --unix,-u file\t\tunix socket (default #{@unix})"
  puts " --file,-f path\t\tfile where to save the sim copy (default #{@file})"
  puts " --bluetooth,-s rfcomm\tbluetooth rfcomm serial port (default #{@bt ? @bt : 'self discovery'})"
  puts " --verbosity,-v\t\tdebug verbosity 0..5 (default #{$verbosity})"
end

#==========
#== main ==
#==========

# parse CLI arguments
while arg=ARGV.shift do
  
  case arg
  when "--help","-h"
    print_help
    exit 0
  when "--type","-t"
    param = ARGV.shift
    @type = param if param
  when "--socket","-s"
    param = ARGV.shift
    @socket = param if param
  when "--port","-p"
    param = ARGV.shift.to_i
    @port = param if param
  when "--host","-l"
    param = ARGV.shift
    @host = param if param
  when "--unix","-u"
    param = ARGV.shift
    @unix = param if param
  when "--file","-f"
    param = ARGV.shift
    @file = param if param
  when "--bluetooth","-s"
    param = ARGV.shift
    @bt = param if param
  when "--verbosity","-v"
    param = ARGV.shift.to_i
    $verbosity = param if param
  else
    puts "unknown argument #{arg}"
    exit 0
  end
end

# create IO
case @socket
when "tcp"
  require 'socket'
  io = TCPSocket.open(@host,@port)
when "unix"
  require 'socket'
  io = UNIXSocket.open(@unix)
when "bt"
  #sudo gem install serialport (http://rubygems.org/gems/serialport)
  require 'rubygems'
  require 'serialport'
  if @bt then
    io = SerialPort.new(@bt)
  else
    require './tools/bluetooth_sap_serial.rb'
    bt = BluetoothSAPSerial.new
    # using SerialPort because reading the File does not work (have to find right stty options)
    io = SerialPort.new(bt.connect)
  end
else
  raise "please defined which socket to use"
end

case @type
when "demo"
  # create client
  @client = Client.new(io)
  @client.start
  @client.connect

  # get ATR
  atr = @client.atr
  puts atr ? "ATR: #{atr.to_hex_disp}" :  "could not get ATR"

  # get IMSI
  imsi = read_ef([MF,DF_GSM,EF_IMSI])
  # byte 1 is the length of the IMSI
  imsi_length = imsi[0]
  imsi = imsi[1,imsi_length]
  # first nibble is for parity check (not done)
  imsi = imsi.nibble_str[1..-1]
  puts "IMSI : "+imsi

  # run A38 algo
  # the rands
  rands = []
  4.times do |i|
    rands << [(i<<4)+i]*16
  end
  # the results
  puts "some KCs (RAND SRES Kc):"
  rands.each do |r|
    response = a38(r)
    puts "  - #{r.to_hex_disp.gsub(' ','')} #{response[0,4].to_hex_disp.gsub(' ','')} #{response[4..-1].to_hex_disp.gsub(' ','')}"
  end

  @client.disconnect
when "info"
  @client = Info.new(io)
  @client.display
  @client.close
when "copy"
  @client = Copy.new(io)
  @client.copy(@file)
  @client.close
else
  raise "please defined which type to use"
end

# close client_io
io.close
bt.close if @socket=="bt" and !@bt
