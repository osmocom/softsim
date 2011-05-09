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
# this programm will display information stored in the SIM
require 'sap/client'
require 'lib/apdu'

#=============
#== methods ==
#=============

class Info

  include APDU
  
  SERVICES = ["CHV1 disable function",
    "Abbreviated Dialling Numbers (ADN)",
    "Fixed Dialling Numbers (FDN)",
    "Short Message Storage (SMS)",
    "Advice of Charge (AoC)",
    "Capability Configuration Parameters (CCP)",
    "PLMN selector",
    "RFU",
    "MSISDN",
    "Extension1",
    "Extension2",
    "SMS Parameters",
    "Last Number Dialled (LND)",
    "Cell Broadcast Message Identifier",
    "Group Identifier Level 1",
    "Group Identifier Level 2",
    "Service Provider Name",
    "Service Dialling Numbers (SDN)",
    "Extension3",
    "RFU",
    "VGCS Group Identifier List (EFVGCS and EFVGCSS)",
    "VBS Group Identifier List (EFVBS and EFVBSS)",
    "enhanced Multi-Level Precedence and Pre-emption Service",
    "Automatic Answer for eMLPP",
    "Data download via SMS-CB",
    "Data download via SMS-PP",
    "Menu selection",
    "Call control",
    "Proactive SIM",
    "Cell Broadcast Message Identifier Ranges",
    "Barred Dialling Numbers (BDN)",
    "Extension4",
    "De-personalization Control Keys",
    "Co-operative Network List",
    "Short Message Status Reports",
    "Network's indication of alerting in the MS",
    "Mobile Originated Short Message control by SIM",
    "GPRS",
    "Image (IMG)",
    "SoLSA (Support of Local Service Area)",
    "USSD string data object supported in Call Control",
    "RUN AT COMMAND command",
    "User controlled PLMN Selector with Access Technology",
    "Operator controlled PLMN Selector with Access Technology",
    "HPLMN Selector with Access Technology",
    "CPBCCH Information",
    "Investigation Scan",
    "Extended Capability Configuration Parameters",
    "MExE",
    "Reserved and shall be ignored",
    "PLMN Network Name",
    "Operator PLMN List",
    "Mailbox Dialling Numbers",
    "Message Waiting Indication Status",
    "Call Forwarding Indication Status",
    "Service Provider Display Information",
    "Multimedia Messaging Service (MMS)",
    "Extension 8",
    "MMS User Connectivity Parameters"]

  # provide the IO to the SAP server
  def initialize(io)
    @client = Client.new(io)
    @client.start
    @client.connect
  end
  
  # tell APDU methods how to send
  def transmit_apdu(apdu)
    return @client.apdu(apdu)
  end
  
  # display the information stored on the SIM
  def display
    # get the ATR
    puts "ATR : #{@client.atr.to_hex_disp}"
    
    # verify CHV1
    while chv_enabled? do
      print "enter PIN : "
      $stdout.flush
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
        break
      rescue
        puts "PIN wrong"
      end
    end
    
    # get ICCID
    iccid = read_ef([MF,EF_ICCID])
    # get rid of the padding
    iccid = iccid.nibble_str(true)
    puts "ICCID : "+iccid
    
    # get IMSI
    imsi = read_ef([MF,DF_GSM,EF_IMSI])
    # byte 1 is the length of the IMSI
    imsi_length = imsi[0]
    imsi = imsi[1,imsi_length]
    # first nibble is for parity check (not done)
    imsi = imsi.nibble_str[1..-1]
    puts "IMSI : "+imsi

    # service provider name
    begin
      spn = read_ef([MF,DF_GSM,EF_SPN])
      spn_str = "service provider name : "
      if spn==[0xff]*spn.length then
        spn_str += "empty"
      else
        name = spn[1..-1]
        name.collect!{|b| b==0xff ? nil : b}.compact!
        spn_str += "name #{alphabet(name)}, "
        spn_str += "display off the registered PLMN "
        spn_str += spn[0]&0x01==0 ? "not required" : "required"
        name = spn[1..-1]
        name.collect!{|b| b==0xff ? nil : b}.compact!
        spn_str += ", name #{alphabet(name)} #{spn.to_hex_disp}"
      end
      puts spn_str
    rescue
      puts "no service provider name"
    end

    # get MSISDN
    begin
      msisdns = read_ef([MF,DF_TELECOM,EF_MSISDN])
      msisdn_str = ""
      msisdns.each do |msisdn|
        next if msisdn==[0xff]*msisdn.length
        msisdn_str += "  - "
        alpha_id = msisdn[0,msisdn.length-14]
        msisdn_str += "aplha identifier : #{alphabet(alpha_id)}"
        #msisdn_str += ", BCD number/SSC length : #{msisdn[-14]}"
        npi = case msisdn[-13]&0xf
        when 0
          "unknown"
        when 1
          "ISDN/telephony"
        when 3
          "data"
        when 4
          "telex"
        when 5
          "private"
        else
          "reserved"
        end
        msisdn_str += ", "
        msisdn_str += "numbering plan identifier : #{npi}"
        ton = case (msisdn[-13]>>4)&0x7
        when 0
          "unknown"
        when 1
          "international"
        when 2
          "national"
        when 3
          "network specific"
        when 4
          "short code"
        else
          "reserved"
        end
        msisdn_str += ", "
        msisdn_str += "type of number : #{ton}"
        number = msisdn[-12,msisdn[-14]-1].nibble_str(true)
        number.gsub!(/[Aa]/,"*")
        number.gsub!(/[Bb]/,"#")
        number.gsub!(/[Cc]/," ")
        number.gsub!(/[Dd]/,"§")
        number.gsub!(/[Ee]/,"1")
        msisdn_str += ", "
        msisdn_str += "number : #{number}"
        msisdn_str += ", capability in EF_CCP #{msisdn[-2]}" unless msisdn[-2]==0xff
        msisdn_str += ", entension in EF_EXT #{msisdn[-1]}" unless msisdn[-1]==0xff
        msisdn_str += "\n"
      end
      if msisdn_str.length>0 then
        puts "MSISIDN :"
        puts msisdn_str
      else
        puts "MSISDN empty"
      end
    rescue
      puts "no MSISDN"
    end

    # get PLMsel
    plmn = read_ef([DF_GSM,EF_PLMNSEL])
    # transform to MCC MNC
    print "PLMN selector : "
    plmns = ""
    (plmn.length/3).times do |i|
      mcc = plmn[3*i,2].nibble_str(true)
      mnc = plmn[3*i+2,1].nibble_str
      plmns += "#{mcc} #{mnc}," unless mcc=="" and mnc=="ff"
    end
    puts plmns[0..-2]

    # get higher priority PLMN search period
    hpplmn = read_ef([MF,DF_GSM,EF_HPPLMN])
    puts "higher priority PLMN search period : #{hpplmn[0]*6} min"

    # get FPLMN
    plmn = read_ef([MF,DF_GSM,EF_FPLMN])
    # transform to MCC MNC
    if plmn[0,3]==[0xff]*3 then
      puts "no forbidden PLMN"
    else
      print "forbidden PLMN : "
      plmns = ""
      (plmn.length/3).times do |i|
        mcc = plmn[3*i,2].nibble_str(true)
        mnc = plmn[3*i+2,1].nibble_str
        plmns += "#{mcc} #{mnc}," unless mcc=="" and mnc=="ff"
      end
      puts plmns[0..-2]
    end

    # get PLMNwAcT
    begin
      plmn = read_ef([MF,DF_GSM,EF_PLMNWACT])
      # transform to MCC MNC
      print "user controlled PLMN : "
      plmns = ""
      (plmn.length/5).times do |i|
        mcc = plmn[3*i,2].nibble_str(true)
        mnc = plmn[3*i+2,1].nibble_str
        plmns += "#{mcc} #{mnc}," unless mcc=="" and mnc=="ff"
      end
      puts plmns[0..-2]
    rescue
      puts "no user controlled PLMN"
    end

    # get OPLMNwAcT
    begin
      plmn = read_ef([MF,DF_GSM,EF_OPLMNWACT])
      # transform to MCC MNC
      print "operator controlled PLMN : "
      plmns = ""
      (plmn.length/5).times do |i|
        mcc = plmn[3*i,2].nibble_str(true)
        mnc = plmn[3*i+2,1].nibble_str
        plmns += "#{mcc} #{mnc}," unless mcc=="" and mnc=="ff"
      end
      puts plmns[0..-2]
    rescue
      puts "no operator controlled PLMN"
    end

    # access control class
    acc = read_ef([MF,DF_GSM,EF_ACC])
    puts "access control class :"
    acc=acc[1]+(acc[0]<<8)
    16.times do |b|
      next if b==10
      text = (acc>>b)&0x01==1 ? "allocated" : "not allocted"
      puts "  - ACC #{b} : #{text}"
    end

    # get Kc
    kc = read_ef([MF,DF_GSM,EF_KC])
    puts "Kc [seq.] : #{kc[0,8].to_hex_disp} [#{kc[8]}]"

    # run A38 algo
    # the rands
    rands = []
    16.times do |i|
      rands << [(i<<4)+i]*16
    end
    # the results
    puts "some KCs (RAND SRES Kc) :"
    rands.each do |r|
      response = a38(r)
      puts "  - #{r.to_hex_disp.gsub(' ','')} #{response[0,4].to_hex_disp.gsub(' ','')} #{response[4..-1].to_hex_disp.gsub(' ','')}"
    end

    # get the phase EFPhase
    phase = read_ef([MF,DF_GSM,EF_PHASE])
    case phase[0]
    when 0
      puts "phase : 1"
    when 2
      puts "phase : 2"
    when 3
      puts "phase : 2 and PROFILE DOWNLOAD required"
    else
      puts "phase : unkown"
    end

    # get EFsst
    puts "SIM service table :"
    sst = read_ef([MF,DF_GSM,EF_SST])
    sst.each_index do |i|
      (0..4).each do |j|
        service_nb = i*4+j
        service = SERVICES[service_nb]
        service = "unknown" unless service
        if ((sst[i]>>(j*2))&0x01)==0x01 then
            service_alloc = "allocated"
        else
            service_alloc = "not allocated"
        end
        if ((sst[i]>>(j*2+1))&0x01)==0x01 then
            service_act = "activated"
        else
            service_act = "not activated"
        end
        puts "  - #{service_nb+1} #{service} : #{service_alloc}, #{service_act}"
      end
    end

    # get the phase
    ad = read_ef([MF,DF_GSM,EF_AD])
    puts "administration data :"
    ms = "  - MS operation mode : "
    ms += case ad[0]
    when 0x00
      "normal operation"
    when 0x80
      "type approval operations"
    when 0x01
      "normal operation + specific facilities"
    when 0x81
      "type approval operations + specific facilities"
    when 0x02
      "maintenance (off line)"
    when 0x04
      "cell test operation"
    end
    puts ms
    ofm = "  - OFM (Operational Feature Monitor) : "
    ofm += ad[2]&0x01==0x00 ? "disabled" : "enabled"
    puts ofm
    if ad.length>3 then
        puts "  - length of MNC in the IMSI : #{ad[3]}"
    end

    # location information
    loci = read_ef([MF,DF_GSM,EF_LOCI])
    puts "location informtion :"
    puts "  - TMSI : #{loci[0,4].to_hex_disp.gsub(' ','')}"
    puts "  - LAI : #{loci[4,5].to_hex_disp.gsub(' ','')}"
    puts "  - TMSI TIME : #{loci[9]==0 ? 'infinite' : (loci[9]*6).to_s+' min'}"
    status = "  - location update status : "
    status += case loci[9]&0x7
    when 0
      "updated"
    when 1
      "not updated"
    when 2
      "PLMN not allowed"
    when 3
      "location area not allowed"
    else
      "reserved"
    end
    puts status
  end
  
  def close
    @client.disconnect
  end
end
