#!/usr/bin/env ruby
require 'server'
require 'socket'
require 'xml'

class String
  # convert a hexadecimal string into binary array
  def hex2arr
    arr = []
    (self.length/2).times do |i|
      arr << self[i*2,2].to_i(16)
    end
    return arr
  end
end

# SAP server using a SIM backup file
class SIMServer < Server

  def initialize(io,path="sim.xml")
    super(io)
    @xml_path = path
  end

  # read file
  def connect

    begin
      xml = IO.read(@xml_path)
      doc = XML::Parser.string(xml)
      @card = doc.parse
    rescue
      puts "can't read #{@xml_path}"
      status = create_message("STATUS_IND",[[0x08,[0x02]]])
      send(status)
      sleep 1
      redo
    end

    # card ready
    # ["StatusChange",["Card reset"]]
    status = create_message("STATUS_IND",[[0x08,[0x01]]])
    send(status)
    log("server","connection established. SIM loaded",3)
  end

  # get ATR
  def atr
    raise "connect to card to get ATR" unless @card
    return @card.find_first("/sim")["atr"].hex2arr
  end

  # send APDU and get response
  def apdu(request)
    raise "connect to card to send APDU" unless @card
    raise "not implemented"
    response = @card.transmit(request.pack('C*')).unpack("C*")
    return response
  end

end

# demo application, using TCP socket
socket = TCPServer.new("localhost",1337)
io = socket.accept
server = SIMServer.new(io)
server.start