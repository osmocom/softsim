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
require 'lib/server'
require 'rubygems'
require 'smartcard'
=begin
need to install
sudo aptitude install ruby ruby-dev rubygems
sudo aptitude install libpcsclite1 libpcsclite-dev libruby
sudo gem install smartcard (http://www.rubygems.org/gems/smartcard)
=end

# SAP server using PCSC for the card
class PCSCServer < Server

  # provide the io to listen to
  # TODO : choose which reader to use
  def initialize(io)
    super(io)
    
    # get PCSC context
    begin
      @context = Smartcard::PCSC::Context.new
    rescue Smartcard::PCSC::Exception => e
      puts "PCSC not available. please start PCSC"
      sleep 1
      retry
    end
      
    # get all readers
    begin
      readers = @context.readers
    rescue Smartcard::PCSC::Exception => e
      puts "no reader available. please connect a card reader"
      sleep 1
      retry
    end
    
    # one reader required
    while readers.size==0 do
      puts "no reader available. connect a reader"
      sleep 1
      readers = @context.readers
    end
    
    # use the first reader
    @reader = readers.first
    puts "using reader : #{@reader}"
    
  end

  # connect to card
  def connect

    # connect to the card
    begin
      @card = Smartcard::PCSC::Card.new(@context,@reader,:exclusive,:t0)
    rescue Smartcard::PCSC::Exception => e
      # wait for a card
      puts "no card available. insert card"
      sleep 1
      retry
    end

    return true
  end
  
  def disconnect
    @card.disconnect
    @context.release
  end

  # get ATR
  def atr
    raise "connect to card to get ATR" unless @card
    return @card.info[:atr].unpack("C*")
  end

  # send APDU and get response
  def apdu(request)
    raise "connect to card to send APDU" unless @card
    response = @card.transmit(request.pack('C*')).unpack("C*")
    return response
  end

end
