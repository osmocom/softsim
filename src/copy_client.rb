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
