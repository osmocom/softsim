#!/usr/bin/env ruby
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
# this program is there to start a server

#=============
#== default ==
#=============

# the server to use (pcsc,sim)
@type = "pcsc"
# which IO to use (tcp,unix)
@socket = "tcp"
# tcp port
@port = 1337
# unix socket
@unix = "/tmp/sap.socket"
# sim file
@file = "sim.xml"
# the verbosity (from common)
$verbosity = 1

#=============
#== methods ==
#=============

# show help
def print_help
  puts "demo_server.rb [options]"
  puts ""
  puts "demonstration SAP server, using available implementations"
  puts ""
  puts "options :"
  puts " --help,-h\t\tprint this help"
  puts " --type,-t type\tserver type : pcsc,sim (default #{@type})"
  puts " --socket,-s type\tsocket type : tcp,unix,bt (default #{@socket})"
  puts " --port,-p port\t\ttcp listeing port (default #{@port})"
  puts " --unix,-u file\t\tunix socket (default #{@unix})"
  puts " --file,-f file\t\tfile for sim type (default #{@file})"
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
  when "--unix","-u"
    param = ARGV.shift
    @unix = param if param
  when "--file","-f"
    param = ARGV.shift
    @file = param if param
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
  socket = TCPServer.new("0.0.0.0",@port)
when "unix"
  require 'socket'
  socket = UNIXServer.new(@unix)
else
  raise "please defined which socket to use"
end
# wait for a client to connect
io = socket.accept

case @type
when "pcsc"
  require 'pcsc_server'
  server = PCSCServer.new(io)
when "sim"
  require 'sim_server'
  server = SIMServer.new(io)
else
  raise "unkown server type"
end

# starting the server
server.start

# close IO when finished
io.close
server.close
