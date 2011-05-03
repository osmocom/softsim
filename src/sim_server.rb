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
require 'lib/server'
require 'lib/apdu'
require 'socket'
require 'xml'

# SAP server using a SIM backup file
class SIMServer < Server

  def initialize(io,path="sim.xml")
    super(io)
    @xml_path = path
  end

#====================
#== main functions ==
#====================

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
    
    # select MF
    node = @card.find_first("/sim/file")
    @selected = node
    @response = node.find_first("./header").content.hex2arr

    # card ready
    return true
  end

  # get ATR
  def atr
    raise "connect to card to get ATR" unless @card
    return @card.find_first("/sim")["atr"].hex2arr
  end

  # send APDU and get response
  def apdu(request)
    raise "connect to card to send APDU" unless @card
    # check the size
    return [0x6f,0x00] unless request.length>=5
    # I can only handle SIM APDU (class A0)
    return [0x6e,0x00] unless request[0]==0xa0
    # default
    data = []
    sw = [0x6f,0x00]
    # the instruction
    case request[1]
    when 0xa4 # SELECT
      # remove the last response
      @response = nil
      # verify the apdu
      if request[2,2]!=[0x00,0x00] then
        # incorrect parameter P1 or P2
        sw = [0x6b,0x00]
      elsif request[4]!=0x02 then
        # incorrect parameter P3
        sw = [0x67,0x02]
      else
        # is the file ID present ?
        if request.length==7 then
		  # check if the directory can be selected
		  file_id = request[5,2]
		  node = select(file_id)
		  if node then
		    # file selected, response awaiting
		    @response = node.find_first("./header").content.hex2arr
		    sw = [0x9f,@response.length]
            log("APDU select","file selected : #{file_id.to_hex_disp}",3)
		  else
		    # out of range (invalid address)
		    sw = [0x94,0x02]
            log("APDU select","file not found/accessible : #{file_id.to_hex_disp}",3)
		  end
		else
		  # out of range (invalid address)
		  sw = [0x94,0x02]
          log("APDU select","file not found/accessible : #{file_id.to_hex_disp}",3)
		end
      end
    when 0xc0 # GET RESPONSE
      # verify the apdu
      if request[2,2]!=[0x00,0x00] then
        # incorrect parameter P1 or P2
        sw = [0x6b,0x00]
      elsif !@response then
        # technical problem with no diagnostic given
        sw = [0x6f,0x00]
      elsif request[4]!=@response.length then
        # incorrect parameter P3
        sw = [0x67,@response.length]
      else
        # return the response
        data = @response
        sw = [0x90,0x00]
      end
    else # unknown instruction byte
      sw = [0x6d,0x00]
    end
    return data+sw
  end

#===================
#== SIM functions ==
#===================

  # select file using the file ID
  # node representing the file is returned
  # nil is return if file does not exist or is unaccessible
  def select(id)
    response = nil
    # get the current directory
    dfs = [0x3f,0x5f,0x7f]
    if dfs.include? @selected["id"][0,2].to_i(16) then
      # selected of a DF
      current_directory = @selected
    else
      # selected is an ED, DF is parent
      current_directory = @selected.find_first("..")
    end
      
    # find file
    if result=current_directory.find_first("./file[@id='#{id.to_hex}']") then
      # any file which is an immediate child of the current directory
      response = result
    elsif dfs.include? current_directory["id"][0,2].to_i(16) and result=current_directory.find_first("../file[@id='#{id.to_hex}']") then
      # any DF which is an immediate child of the parent of the current DF
      response = result
    elsif result=current_directory.find_first("..") and result["id"]==id.to_hex then
      # the parent of the current directory
      response = result
    elsif current_directory["id"]==id.to_hex then
      # the current DF
      response = current_directory
    elsif id==[0x3f,0x00] then
      # the MF
      response = @card.find_first("/sim/file[@id='3f00']")
    else
      # file not found
      response = nil
    end
    # remember new selected file
    @selected = response if response
    
    return response
  end

end
