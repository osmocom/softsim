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
# this class copies all files from the SIM to an xml file
require 'sap/client'
require 'lib/apdu'
require 'xml'

class Copy

  include APDU
  
  # to show the exact file being processed
  VERBOSE = false
  # show file discovery progress
  PROGRESS = true
  
  # create a Copy class
  # io : I/O to the SAP server
  def initialize(io)
    @client = Client.new(io)
    @client.start
    @client.connect
  end
  
  # tell APDU methods how to send
  def transmit_apdu(apdu)
    return @client.apdu(apdu)
  end
  
  # copy the content to a file
  def copy(file="sim.xml")
    @sim = XML::Node.new("sim")
    # get the ATR
    @sim["atr"] = @client.atr.to_hex
    
    # verify CHV1
    while chv_enabled? do

      print "enter PIN : "
      STDOUT.flush
      pin = gets.chomp
      # pin is between 4 and 8 digits
      unless pin.length>=4 and pin.length<=8 and pin.gsub(/\d/,"").length==0 then
        puts "PIN has 4 to 8 digits"
        redo
      end

      # encode pin in T.50 on 8 bytes
      chv = [0xFF]*8
      pin.length.times do |i|
        chv[i]=0x30+pin[i,1].to_i
      end

      # select DF_GSM
      cd [MF,DF_GSM]
      # verify CHV1
      begin
        transmit(CHV1+chv)
        @sim["CHV1"]=pin
        break
      rescue
        puts "PIN wrong"
      end
    end

    # get MF
    puts "reading SIM files"
    mf = explore([MF])
    @sim << mf
    puts "" if PROGRESS and !VERBOSE
    puts "found #{@nb_directories} directories and #{@nb_files} files"

    # get some tuples (run A38 algo)
    puts "getting some A38 tuples"
    a38_node = XML::Node.new("a38")
    # the rands
    rands = []
    16.times do |i|
      rands << [(i<<4)+i]*16
    end
    # the results
    rands.each do |r|
      response = a38(r)
      tuple_node = XML::Node.new("tuple")
      tuple_node["rand"]=r.to_hex
      tuple_node["sres"]=response[0,4].to_hex
      tuple_node["kc"]=response[4..-1].to_hex
      a38_node << tuple_node
    end
    @sim << a38_node

    # write xml in file
    puts "saving SIM files in #{file}"
    xml = XML::Document.new
    xml.root = @sim
    xml.save(file)
  end
  
  # return the file
  # - id : file ID
  # return {:id,:type,:name,:structure,:header,:body}, or nil if file does not exist
  def file(id)

    # the data to return
    to_return = {}

    # select file
    begin
      response = select(id)
    rescue Exception => e
      if e.to_s.include? "file ID not found/pattern not found" then
        return nil
      else
        raise e
      end
    end
    to_return[:header] = response
    # file id
    to_return[:id] = [response[4],response[5]]
    to_return[:name]=FILE_ID[(to_return[:id][0]<<8)+to_return[:id][1]]
    # file type
    type = case response[6]
    when 0
      "RFU"
    when 1
      "MF"
    when 2
      "DF"
    when 4
      "EF"
    else
      "unknown"
    end
    to_return[:type] = type

    # read EF
    if response[6]==0x04 then

      # structure
      structure = case response[13]
      when 0
        "transparent"
      when 1
        "linear fixed"
      when 3
        "cyclic"
      else
        "unknown"
      end
      to_return[:structure] = structure

      # do I have the right to read ?
      nibble = (response[8]>>4)&0x0f
      read_right = (nibble==0 or nibble==1)

      if read_right then
        size = (response[2]<<8)+response[3]
        # read ef (depending on the type of file)
        if response[13]==0x00 then # transparent file (TS 51.011 9.3)
          response = transmit(READ_BINARY+[0x00,0x00]+[size&0xFF])[0]
          to_return[:body] = response
          if size>0xFF then
            response = transmit(READ_BINARY+[0x01, 0x00]+[(size>>8)&0xFF])[0]
            to_return[:body] += response
          end
        else # linear fixed or cyclic
          record_size = response[14]
          to_return[:body] = []
          # read all records
          (1..size/record_size).each do |i|
            response = transmit(READ_RECORD+[i,0x04,record_size])[0]
            to_return[:body] << response
          end
        end
      end
      
    end

    return to_return
  end

  # returns a node from the file data
  def file2node(data)

    node = XML::Node.new("file")
    node["id"]=data[:id].to_hex
    node["name"]=data[:name] if data[:name]
    node["type"]=data[:type]
    node << XML::Node.new("header",data[:header].to_hex)
    if data[:type]=="EF" then
      node["structure"]=data[:structure]
      if data[:body] then# if I can read the body
        if data[:structure]=="transparent" then
          node << XML::Node.new("body",data[:body].to_hex)
        else # linear fixed or cyclic
          body_node = XML::Node.new("body")
          data[:body].each do |record|
            body_node << XML::Node.new("record",record.to_hex)
          end
          node << body_node
        end
      end
    end
    return node
  end

  # get all the files in the current directory
  # does a recursive call
  # files are saved in the xml file
  # path is an arry of MF/DF
  # return xml node representing the folder and content
  def explore(path)

    puts "exploring #{path.flatten.to_hex_disp}" if VERBOSE
    # go to parent folder
    cd path[0..-2]
    # get info and select folder
    data = file(path[-1])
    return nil unless data
    node = file2node(data)

    # read all EF
    ef_id = EF_LEVELS[path.length]
    if ef_id then
      0x100.times do |i|
        id = [ef_id,i]
        begin
          data=file(id)
          next unless data # if file does not exist
          if VERBOSE then
            puts "found EF #{id.to_hex_disp}"
          elsif PROGRESS
            print "."
            STDOUT.flush
          end
          ef_node = file2node(data)
          node << ef_node
          @nb_files = 0 unless @nb_files
          @nb_files += 1
        rescue Exception => e
          puts "file error : #{e.to_s}"
          select_decode(select(id))
        end
      end
    end

    # read all DF
    df_id = DF_LEVELS[path.length]
    if df_id then
      # read all DF
      0x100.times do |i|
        id = [df_id,i]
        df_node = explore(path+[id])
        next unless df_node
        if VERBOSE then
          puts "found DF #{id.to_hex_disp}"
        elsif PROGRESS
          print ","
          STDOUT.flush
        end
        node << df_node
        @nb_directories = 0 unless @nb_directories
        @nb_directories += 1
      end
    end

    return node
  end
  
  # close the copy
  def close
    @client.disconnect
  end
end
