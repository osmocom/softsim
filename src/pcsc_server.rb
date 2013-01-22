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
require './sap/server.rb'
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
  def initialize(io)
    super(io)
  end
  
  # get the reader and the card
  # return if connection to card succeeded
  def select_card
  
    # get PCSC context
    begin
      @context = Smartcard::PCSC::Context.new
    rescue Smartcard::PCSC::Exception => e
      puts "PCSC not available. please start PCSC"
      return false
    end
    
    # get all readers
    begin
      readers = @context.readers
    rescue Smartcard::PCSC::Exception => e
      puts "no reader available. please connect a card reader"
      return false
    end
    
    # one reader required
    if readers.size==0 then
      puts "no reader available. connect a reader"
      return false
      # select reader
    elsif readers.size==1 then
      # use the first reader
      reader = readers.first
    elsif @reader_id
      # reader already selected
    else
      # select reader
      puts "readers:"
      readers.each_index do |i|
        puts "#{i}) #{readers[i]}"
      end
      reader = nil
      until reader do
        print "select reader [0]: "
        @reader_id = gets.chomp.to_i
        reader = readers[@reader_id]
      end
    end
    puts "using reader: #{reader}"
    
    # connect to the card
    verb = true
    begin
      @card = Smartcard::PCSC::Card.new(@context,reader,:exclusive,:t0)
    rescue Smartcard::PCSC::Exception
      puts "no card inside. insert smart card"
      return false
    end
    
    puts "connected to card"
    return true
  end

  # connect to card
  def connect

    # connect to card
    sleep 1 until select_card
    
    return true
  end
  
  # release card and context
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
    begin
      response = @card.transmit(request.pack('C*')).unpack("C*")
    rescue Smartcard::PCSC::Exception => e
      tries = 0 unless tries
      tries += 1
      if tries <= 3 then
        puts "PCSC bug (try #{tries})"
        sleep 5
        retry
      else
        raise e if tries>=3
      end
    end
    return response
  end

end
