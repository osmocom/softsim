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
# this librarie is to centralise the APDU related work
$KCODE = 'UTF8'
require 'jcode'

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

#===============
#== constants ==
#===============

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
      EF_KC = [0x6F,0x20] # TS 51.011 10.3.3
      EF_PLMNSEL = [0x6F,0x30] # TS 51.011 10.3.4
      EF_HPPLMN = [0x6F,0x31] # TS 51.011 10.3.5
      EF_FPLMN = [0x6F,0x7B] # TS 51.011 10.3.16
      EF_PLMNWACT = [0x6F,0x60] # TS 51.011 10.3.35
      EF_OPLMNWACT = [0x6F,0x61] # TS 51.011 10.3.36
      EF_PHASE = [0x6F,0xAE] # TS 51.011 10.3.19
      EF_SST = [0x6F,0x38] # TS 51.011 10.3.7
      EF_AD = [0x6F,0xAD] # TS 51.011 10.3.18
      EF_LOCI = [0x6F,0x7E] # TS 51.011 10.3.17
      EF_SPN = [0x6F,0x46] # TS 51.011 10.3.11
      EF_ACC = [0x6F,0x78] # TS 51.011 10.3.15
    DF_TELECOM = [0x7F,0x10]
      EF_SMS = [0x6F,0x3C] # TS 51.011 10.5.3
      EF_SMSS = [0x6F,0x43] # TS 51.011 10.5.7
      EF_MSISDN = [0x6F,0x40] # TS 51.011 10.5.5

  # File IF (from ETSI TS 151 011 V4.9.0, figure 8)
  FILE_ID = {
    0x3f00 => "MF",
    0x7f20=>"DF_GSM",0x7f10=>"DF_TELECOM",0x7f22=>"DF_IS-41",0x7f23=>"DF_FR-CTS",0x2fe2=>"EF_ICCID",0x2f05=>"EF_ELP",
    0x6f3a=>"EF_ADN",0x6f3b=>"EF_FDN",0x6f3c=>"EF_SMS",0x6f3d=>"EF_CCP",0x6f40=>"EF_MSISDN",
    0x6f42=>"EF_SMSP",0x6f43=>"EF_SMSS",0x6f44=>"EF_LND",0x6f47=>"EF_SMSR",0x6f49=>"EF_SDN",
    0x6f4a=>"EF_EXT1",0x6f4b=>"EF_EXT2",0x6f4c=>"EF_EXT3",0x6f4d=>"EF_BDN",0x6f4d=>"EF_EXT4",
    0x5f50=>"DF_GRAPHICS",0x4f20=>"EF_IMG",0x6f4f=>"EF_ECCP",
    0x5f30=>"DF_IRIDIUM",0x5f31=>"DF_GLOBST",0x5f32=>"DF_ICO",0x5f33=>"DF_ACeS",
    0x5f40=>"DF_EIA/TIA-553",0x5f60=>"DF_CTS",0x5f70=>"DF_SoLSA",0x4f30=>"EF_SAI",0x4F31=>"EF_SLL",
    0x5f3c=>"DF_MExE",0x4f40=>"EF_MExE-ST",0x4f41=>"EF_ORPK",0x4f42=>"EF_ARPK",0x4f43=>"EF_TPRPK",
    0x6f05=>"EF_LP",0x6f07=>"EF_IMSI",0x6f20=>"EF_Kc",0x6f2c=>"ED_DCK",0x6f30=>"EF_PLMNsel",0x6f31=>"EF_HPPLMN",
    0x6f32=>"EF_CNL",0x6f37=>"EF_ACMmax",0x6f38=>"EF_SST",0x6f39=>"EF_ACM",0x6f3e=>"GID1",0x6f3f=>"GID2",
    0x6f41=>"EF_PUCT",0x6f45=>"EF_CBMI",0x6f46=>"EF_SPN",0x6f48=>"EF_CBMID",0x6f74=>"EF_BCCH",0x6f78=>"EF_ACC",
    0x6f7b=>"EF_FPLMN",0x6f7e=>"EF_LOCI",0x6fad=>"EF_AD",0x6fae=>"EF-PHASE",0x6fb1=>"EF_VGCS",0x6fba=>"EF_VGCSS",
    0x6fb3=>"EF_VBS",0x6fb4=>"EF_VBSS",0x6fb5=>"EF_eMLPP",0x6fb6=>"EF_AAeM",0x6fb7=>"EF_ECC",0x6f50=>"EF_CBMIR",
    0x6f51=>"EF_NIA",0x6f52=>"EF_KcGPRS",0x6f53=>"EF_LOCIGPRS",0x6f54=>"EF_SUME",0x6f58=>"EF_CMI",0x6f60=>"EF_PLMNwEAcT",
    0x6f61=>"EF_OPLMNwAcT",0x6f62=>"EF_HPLMNAcT",0x6f63=>"EF_CPBCCH",0x6f64=>"EF_INVSCAN",0x6fc5=>"EF_PNN",0x6fc6=>"EF_OPL",
    0x6fc7=>"EF_MBDN",0x6fc8=>"EF_EXT6",0x6fc9=>"EF_MBI",0x6fca=>"EF_MWIS",0x6fcb=>"EF_CFIS",0x6fcc=>"EF_EXT7",
    0x6fcd=>"EF_SPDI",0x6fce=>"EF_MMSN",0x6fcf=>"EF_EXT8",0x6fd0=>"EF_MMSIFP",0x6fd1=>"EF_MMSUP",0x6fd2=>"EF_MMSUCP"
  }
  
  # GSM alphabet (7 bits)
  # 0x1b escape caharacter is now space
  GSM_ALPHABET = "@£$¥èéùìòÇ\rØø\nÅåΔ_ΦΓΛΩΠΨΣΘΞ ÆæßÉ !\"#¤%&'()*=,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
  # not defined is a space
  EXTENDED_ALPHABET = "                    ^                   {}     \\            [~] |                                    €                          "

#=============
#== methods ==
#=============
  
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

  # get the status (current directory)
  def status
    begin
      response, sw1, sw2 = transmit(STATUS+[0x00])
    rescue
      return nil
    end
    response, sw1, sw2 = transmit(GET_RESPONSE+[sw2])
    return response
  end
  
  # RUN GSM ALGORITHM
  def a38(rand)
    # am I in DF_GSM ?
    pwd = status()
    cd [MF,DF_GSM] unless pwd and pwd[4,2]==DF_GSM

    # run algo
    response, sw1, sw2 = transmit(A38+rand)
    response, sw1, sw2 = transmit(GET_RESPONSE+[sw2])

    return response
  end

  # change directory
  # - path : array of files (EF/DF) to browse
  def cd(path)
    # change each folder
    path.each do |folder|
      # select folder
      response = select(folder)
      # verify it's a folder (MF or DF)
      raise "#{folder.to_hex_disp} is not a folder" unless response[6]==1 or response[6]==2
    end
  end
  
  # read an elementary file
  # - path : array of files (directory+ef) to browse
  # returns the content (binary or record)
  def read_ef(path)

    # browse the path
    cd path[0..-2]
    # select file
    response = select(path[-1])
    size = (response[2]<<8)+response[3]
    # verify it's really and EF (TS 51.011 9.3)
    if response[6]==0x04 then
      # read ef (depending on the type of file)
      if response[13]==0x00 then # transparent file (TS 51.011 9.3)
        response, sw1, sw2 = transmit(READ_BINARY+[0x00,0x00]+[size&0xFF])
        to_return = response
        if size>0xFF then
          response, sw1, sw2 = transmit(READ_BINARY+[0x01, 0x00]+[(size>>8)&0xFF])
          to_return += response
        end
      else # linear fixed or cyclic
        record_size = response[14]
        to_return = []
        # read all records
        (1..size/record_size).each do |i|
          response = transmit(READ_RECORD+[i,0x04,record_size])[0]
          to_return << response
        end
      end
    else
      raise "selection is not an EF"
      # TODO : implement the MF/DF reading
    end

    return to_return
  end

  # is the CHV1/PIN required
  def chv_enabled?
    # goto DF_GSM and verify if CHV is required
    cd [MF]
    response = select(DF_GSM)
    # check if enabled
    chv_enabled = (response[13]>>7)&0x01==0
    chv_tries = response[18]&0x0f
    if chv_enabled and chv_tries==0 then
      puts "no CHV1 try left. enter PUK1 on your phone"
      exit 0
    elsif chv_enabled
      puts "#{chv_tries} CHV1 tries left"
    end

    return chv_enabled
  end

  # convert a 7-bit GSM alphabet text into UTF8
  def alphabet(text)
    converted = ""
    escape = false
    text.each do |c|
      if escape then # extended table
        converted += EXTENDED_ALPHABET.char_at(c)
        escape = false
      else # gsm 7 bit alphabet
        if c==0x1b then
          escape = true
        else
          converted += GSM_ALPHABET.char_at(c)
        end
      end
    end
    return converted
  end

end
