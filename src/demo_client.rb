#!/usr/bin/env ruby
=begin
This file is part of SAP.

SAP is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

SAP is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with SAP.  If not, see <http://www.gnu.org/licenses/>.

Copyright (C) 2011 Kevin "tsaitgaist" Redon kevredon@mail.tsaitgaist.info
=end
# This programm will create a client which can be used to test servers
require 'lib/client'
require 'lib/apdu'

#=================
#== client type ==
#=================

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
  require 'lib/bluetooth_sap_serial'
  #sudo gem install serialport (http://rubygems.org/gems/serialport)
  require 'rubygems'
  require 'serialport'
=begin
to monitor bluetooth traffic
sudo aptitude install bluez-hcidump
sudo hcidump -x -i hci0 rfcomm
=end
  bt = BluetoothSAPSerial.new
  # using SerialPort because reading the File does not work (have to find right stty options)
  io = SerialPort.new(bt.connect)
else
  raise "please defined which client to use"
end

#===============
#== constants ==
#===============

# to debug the program
# shows APDU IO
DEBUG = true
# the verbosity from common
VERBOSE = 0

#=============
#== methods ==
#=============

include APDU

# tell APDU methods how to send
def transmit_apdu(apdu)
  return @client.apdu(apdu)
end

#==========
#== main ==
#==========

@client = Client.new(io,VERBOSE)
@client.start
@client.connect
atr = @client.atr
puts atr ? "ATR : #{atr.to_hex_disp}" :  "could not get ATR"
# select MF
transmit(GET_RESPONSE+[0x1a])
select(MF)
@client.disconnect

# close client_io
case client_io
when :tcp
  io.close
when :bt
  io.close
  bt.close
end
