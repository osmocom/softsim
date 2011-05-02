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
# this librarie is to centralise the APDU related work

# transform binary string into readable hex string
class String
  def to_hex_disp
    to_return = ""
    each_byte do |b|
      to_return += b.to_s(16).rjust(2,"0")
      to_return += " "
    end
    return to_return[0..-2].upcase
  end

  def to_hex
    to_return = ""
    each_byte do |b|
      to_return += b.to_s(16).rjust(2,"0")
    end
    #to_return = "0x"+to_return
    return to_return.downcase
  end
  
  # convert a hexadecimal string into binary array
  def hex2arr
    arr = []
    (self.length/2).times do |i|
      arr << self[i*2,2].to_i(16)
    end
    return arr
  end
end

# reverse the nibbles of each byte
class Array
  # print the nibbles (often BCD)
  # - padding : the 0xf can be ignored (used as padding in BCD)
  def nibble_str(padding=false)
    # get nibble representation
    to_return = collect { |b| (b&0x0F).to_s(16)+(b>>4).to_s(16) }
    to_return = to_return.join
    # remove the padding
    to_return.gsub!('f',"") if padding
    return to_return
  end

  def to_hex_disp
    to_return = ""
    each do |b|
      to_return += b.to_s(16).rjust(2,"0")
      to_return += " "
    end
    return to_return[0..-2].upcase
  end

  def to_hex
    to_return = ""
    each do |b|
      to_return += b.to_s(16).rjust(2,"0")
    end
    #to_return = "0x"+to_return
    return to_return.downcase
  end
end

module APDU

  # APDU constants (TS 102.221 10.1.2)
  # SIM Class code (TS 51.011 9.2)
  CLASS = 0xA0
  # add the address (2 bytes) to the select command (TS 51.011 9.2.1)
  SELECT = [CLASS, 0xA4, 0x00, 0x00, 0x02]
  # get the response after a select (TS 51.011 9.1)
  # add the length (P3) to get the information (= SW2 after SELECT)
  GET_RESPONSE = [CLASS, 0xC0, 0x00, 0x00]
  STATUS = [CLASS, 0xF2, 0x00, 0x00]
  # add the length (P3) to have complete command
  READ_BINARY = [CLASS,0xB0]
  READ_RECORD = [CLASS,0xB2]
  UPDATE_RECORD = [CLASS,0xDC]
  CHV1 = [CLASS,0x20,0x00,0x01,0x08]
  A38 = [CLASS,0x88,0x00,0x00,0x10]

  # file address (TS 51.011 10.7, page 105)
  MF = [0x3F,0x00]
    EF_ICCID = [0x2F,0xE2]
    DF_GSM = [0x7F,0x20]
      EF_IMSI = [0x6F,0x07] # TS 51.011 10.3.2
    DF_TELECOM = [0x7F,0x10]
      EF_MSISDN = [0x6F,0x40] # TS 51.011 10.5.5
  
  # send APDU byte array
  # return : APDU response
  def transmit_apdu(apdu)
    raise NotImplementedError 
  end
  
  # handle APDU (bayte array) to send APDU
  # returns [response,sw1,sw2]
  def transmit(apdu)

    # send APDU
    resp = transmit_apdu(apdu)
    # parse response
    response = resp[0..-3]
    sw1 = resp[-2]
    sw2 = resp[-1]
    sw_check(sw1,sw2)

    return response,sw1,sw2
  end
  
  # check if there is an error
  # TS 51.011 9.4
  def sw_check(sw1,sw2)

    # verb for the exception
    head = "SW error. "
    category = ""
    sw = " (#{sw1.to_s(16).rjust(2,'0')},#{sw2.to_s(16).rjust(2,'0')})"
    error = nil

    case sw1
    when 0x94
      category = "referencing management"
      case sw2
      when 0x00
        error = "no EF selected"
      when 0x02
        error = "out of range (invalid address)"
      when 0x04
        error = "file ID not found/pattern not found"
      when 0x08
        error = "file is inconsistent with the command"
      else
        error = "unknown"
      end
    when 0x98
      if sw2==0x04 then
        error = "not allowed or wrong PIN"
      else
        error = "security error"
      end
    when 0x6B
      error = "incorrect P1 or P2"
    when 0x67
      category = "application independent errors"
      error = "incorrect P3"
    else
      if sw1!=0x9F and sw1!=0x90 then
        error = "unknown response"
      end
    end

    raise head+category+" : "+error+sw if error
  end

  # select a file. returns the response
  def select(file)
    # select file
    response, sw1, sw2 = transmit(SELECT+file)
    # get response
    response, sw1, sw2 = transmit(GET_RESPONSE+[sw2])

    return response
  end
end
