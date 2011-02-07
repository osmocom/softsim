#!/usr/bin/env ruby
require 'server'
require 'socket'
=begin
need to install
sudo aptitude install ruby ruby-dev rubygems
sudo aptitude install libpcsclite1 libpcsclite-dev libruby
sudo gem install smartcard (http://www.rubygems.org/gems/smartcard)
=end
require 'rubygems'
# smartcard 0.5.1 can not handle T=0 because of a FFI::Enum bug
# patch existing
require 'smartcard'

# SAP server using PCSC for the card
class PCSCServer < Server

  # provide the io to listen to
  def initialize(io)
    super(io)
  end

  # connect to card
  # TODO : choose which reader to use
  def connect
    
    # get PCSC context
    context = Smartcard::PCSC::Context.new
    # get all readers
    readers = context.readers
    # one reader required
    if readers.size==0 then
      puts "no reader available. connect a reader"
      # info client ["StatusChange",["Card not accessible"]]
      status = create_message("STATUS_IND",[[0x08,[0x02]]])
      send(status)
      while readers.size==0 do
        context = Smartcard::PCSC::Context.new
        readers = context.readers
        sleep 1
      end
    end
    # use the first reader
    reader = readers.first
    puts "using reader : #{reader}"

    # connect to the card
    begin
      @card = Smartcard::PCSC::Card.new(context,reader,:exclusive,:t0)
    rescue Smartcard::PCSC::Exception => e
      # wait for a card
        puts "no card available. insert card"
        # info client ["StatusChange",["Card not accessible"]]
        status = create_message("STATUS_IND",[[0x08,[0x02]]])
        send(status)
        begin
          @card = Smartcard::PCSC::Card.new(context,reader,:exclusive,:t0)
        rescue Smartcard::PCSC::Exception => e
          sleep 1
          retry
        end
    end

    # card ready
    # ["StatusChange",["Card reset"]]
    status = create_message("STATUS_IND",[[0x08,[0x01]]])
    send(status)
    puts "connected to card"
    log("server","SIM ready (reset)",3)
  end

  # get ATR
  def atr
    raise "connect to card to get ATR" unless @card
    return @card.info[:atr].unpack("C*")
  end

end

# demo application, using TCP socket
socket = TCPServer.new("localhost",1234)
io = socket.accept
server = PCSCServer.new(io)
server.start