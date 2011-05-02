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
# this program is there to start a server
require 'socket'
require 'pcsc_server'
require 'sim_server'

# the io the server should use (:tcp, :unix)
io_type = :tcp
# the server to use (:pcsc, :sim)
server_type = :pcsc

# create the IO
case io_type
when :tcp
  TCP_HOST = "localhost"
  TCP_PORT = "1337"
  socket = TCPServer.new(TCP_HOST,TCP_PORT)
when :unix
  UNIX = "/tmp/sap_server.socket"
  socket = UNIXServer.new(APDU_SOCKET)
else
  raise "unkown IO type"
end

# wait for a client to connect
io = socket.accept

case server_type
when :pcsc
  server = PCSCServer.new(io)
when :sim
  server = SIMServer.new(io)
else
  raise "unkown server type"
end

# starting the server
server.start

# close IO when finished
io.close
server.close
