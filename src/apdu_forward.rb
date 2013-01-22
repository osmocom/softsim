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
# this programm will forward APDU from an IO to a SAP server
require './sap/client.rb'
require 'socket'

SAP_HOST = "localhost"
SAP_PORT = "1337"
APDU_SOCKET = "/tmp/apdu.socket"

# wait for a client to connect
socket = UNIXServer.new(APDU_SOCKET)
io = socket.accept

# create SAP client to SAP server
sap = TCPSocket.open(SAP_HOST,SAP_PORT)
client = Client.new(sap,0)
client.start
client.connect
atr = client.atr
puts atr ? "ATR : #{atr.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get ATR"

@end = false
until @end do
  activity = IO.select([io])
  begin
    input = activity[0][0].readpartial(0xffff)
    req = input.unpack("C*")
    puts "> #{req.collect{|x| x.to_s(16).rjust(2,'0')}*' '}"
    resp = client.apdu(req)
    puts "< #{resp.collect{|x| x.to_s(16).rjust(2,'0')}*' '}"
    io.write resp.pack("C*")
  rescue EOFError,Errno::EPIPE
    $stderr.puts "source disconnected"
    @end = true
  end
end

io.close
client.disconnect
sap.close
