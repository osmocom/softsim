#!/usr/bin/env ruby
require 'server'
require 'socket'

# SAP server using PCSC for the card
class PCSCServer < Server

  # provide the io to listen to
  def initialize(io)
    super(io)
  end
end

# demo application, using TCP socket
socket = TCPServer.new("localhost",1234)
io = socket.accept
server = PCSCServer.new(io)
server.start