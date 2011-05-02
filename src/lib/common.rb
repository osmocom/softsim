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
require 'stringio'

# the common part of SAP server and client
# it includes :
# - constants
# - message types
# - parameter types
# - message creation
# - message parsing
# - sending and recieving messages
# to implement :
# - state machine (client/server)
# - connect,disconnect,reset,atr,apdu

# SAP common architecture
class SAP

  # make the class abstract
  private :initialize

#===============
#== constants ==
#===============
  
  # SAP table 5.16
  CONNECTION_STATUS = { 0x00 => "OK, Server can fulfill requirements",
    0x01 => "Error, Server unable to establish connection",
    0x02 => "Error, Server does not support maximum message size",
    0x03 => "Error, maximum message size by Client is too small",
    0x04 => "OK, ongoing call"
  }
  # SAP table 5.18
  RESULT_CODE = { 0x00 => "OK, request processed correctly",
    0x01 => "Error, no reason defined",
    0x02 => "Error, card not accessible",
    0x03 => "Error, card (already) powered off",
    0x04 => "Error, card removed",
    0x05 => "Error, card already powered on",
    0x06 => "Error, data not available",
    0x07 => "Error, not supported"
  }
  # SAP table 5.19
  STATUS_CHANGE = { 0x00 => "Unknown Error",
    0x01 => "Card reset",
    0x02 => "Card not accessible",
    0x03 => "Card removed",
    0x04 => "Card inserted",
    0x05 => "Card recovered"
  }
  
  # SAP table 5.15
  # parameter_type (hash) :
  # - :name = description of the parameter
  # - :length = size of the parameter (-1 means undefined)
  # - :id = parameter id (1 byte)
  PARAMETERS = []

  # create a parameter type and add it to the catalogue
  def self.add_parameter_type (name,length,id)
     PARAMETERS << {
      :name => name,
      :length => length,
      :id => id
    }
  end

  # populate parameter catalogue
  add_parameter_type("MaxMsgSize",2,0x00)
  add_parameter_type("ConnectionStatus",1,0x01)
  add_parameter_type("ResultCode",1,0x02)
  add_parameter_type("DisconnectionType",1,0x03)
  add_parameter_type("CommandAPDU",-1,0x04)
  add_parameter_type("CommandAPDU7816",2,0x10)
  add_parameter_type("ResponseAPDU",-1,0x05)
  add_parameter_type("ATR",-1,0x06)
  add_parameter_type("CardReaderdStatus",1,0x07)
  add_parameter_type("StatusChange",1,0x08)
  add_parameter_type("TransportProtocol",1,0x09)

  # SAP table 5.1
  # array of message_types
  # message_type (hash) :
  # - :name = description of the message
  # - :client_to_server = can it be sent from client to server
  # - :server_to_client = can it be sent from server to client
  # - :id = message id (1 byte)
  # - :parameters = array of [parameters,mandatory]
  MESSAGES = []

  # create a message type and add it to the message catalogue
  def self.add_message_type (name,client_to_server,id,parameters)
    # find the parameter
    params = []
    parameters.each do |parameter|
      param = PARAMETERS.collect{ |x| x[:id]==parameter[0] ? x : nil }.compact
      if param.size == 1 then
        params << [param,parameter[1]]
      else
        puts "parameter not found in catalogue : #{parameter[0]}"
      end
    end
    MESSAGES << {
      :name => name,
      :client_to_server => client_to_server,
      :server_to_client => !client_to_server,
      :id => id,
      :parameters => params
    }
  end
  
  # populate parameter catalogue
  add_message_type("CONNECT_REQ",true,0x00,[[0x00,true]])
  add_message_type("CONNECT_RESP",false,0x01,[[0x01,true],[0x00,false]])
  add_message_type("DISCONNECT_REQ",true,0x02,[])
  add_message_type("DISCONNECT_RESP",false,0x03,[])
  add_message_type("DISCONNECT_IND",false,0x04,[[0x03,true]])
  add_message_type("TRANSFER_APDU_REQ",true,0x05,[[0x04,false],[0x10,false]])
  add_message_type("TRANSFER_APDU_RESP",false,0x06,[[0x02,true],[0x05,false]])
  add_message_type("TRANSFER_ATR_REQ",true,0x07,[])
  add_message_type("TRANSFER_ATR_RESP",false,0x08,[[0x02,true],[0x06,false]])
  add_message_type("POWER_SIM_OFF_REQ",true,0x09,[])
  add_message_type("POWER_SIM_OFF_RESP",false,0x0A,[[0x02,true]])
  add_message_type("POWER_SIM_ON_REQ",true,0x0B,[])
  add_message_type("POWER_SIM_ON_RESP",false,0x0C,[[0x02,true]])
  add_message_type("RESET_SIM_REQ",true,0x0D,[])
  add_message_type("RESET_SIM_RESP",false,0x0E,[[0x02,true]])
  add_message_type("TRANSFER_CARD_READER_STATUS_REQ",true,0x0F,[])
  add_message_type("TRANSFER_CARD_READER_STATUS_RESP",false,0x10,[[0x02,true],[0x07,false]])
  add_message_type("STATUS_IND",false,0x11,[[0x08,true]])
  add_message_type("ERROR_RESP",false,0x12,[])
  add_message_type("SET_TRANSPORT_PROTOCOL_REQ",true,0x13,[[0x09,true]])
  add_message_type("SET_TRANSPORT_PROTOCOL_RESP",false,0x14,[[0x02,true]])

#=================
#== SAP methods ==
#=================

  # create a new SAP client/server
  # - io : the Input/Output to monitor
  def initialize(io,verbosity=VERBOSE)

    # the verbose output
    #@verbose = StringIO.new # no output
    @verbose = $> # std output
    @verbosity = verbosity
    # this has to be defined in child class
    # @socket can be any IO
    @io = io
    # the socket loop
    @end = false
    # the typical time to cwait befor a recheck (in sec)
    @wait_time = 0.1
    # the input buffer containing the incoming messages
    @buffer_in = []
    # incoming message queue
    @messages_in = []
  end


  # start listening the connection
  def start
    until @end do
      log("IO","select",3)
      activity = IO.select([@io])
      log("IO","activity",3)
      begin
        input = activity[0][0].readpartial(@max_msg_size)
        log("IO","> (#{input.size}) #{hex(input)}",5)
        @buffer_in += input.unpack("C*")
      rescue EOFError
        $stderr.puts "device disconnected"
        @io.close
        exit 0
      end
      # parse the message from @buffer_in to @messages_in
      parse_messages
      # wait until the buffer_in is empty before processing the messages
      if @buffer_in.size==0 then
        # process messages
        while message=@messages_in.shift do
          # give message to handler
          state_machine(message)
        end
      end
    end
  end

  def set_state (new_state)
    if @state then
      log("state","state changed from #{@state} to #{new_state}",2)
    else
      log("state","state set to #{new_state}",2)
    end
    @state = new_state
  end

#==================
#== to implement ==
#==================

  # the state machine that has to be implemented
  # SAP figure 4.13
  def state_machine(message)
    raise NotImplementedError
  end

  # client : connect to SAP server
  # server : connect to SIM
  # return : successfull connection
  def connect
    raise NotImplementedError
  end

  # client : disconnect from SAP server
  # server : disconnect from SIM card
  # return : successfull disconnection
  def disconnect
    raise NotImplementedError
  end

  # disconnect synonime
  def close
    return disconnect
  end

  # client : ask for the ATR from SAP server (must be connected)
  # server : get ATR from SIM card
  # return : ATR
  def atr
    raise NotImplementedError
  end

  # client : send APDU request to SAP server and get response
  # server : send APDU request to SIM and get response
  # return : APDU response
  def apdu(apdu)
    raise NotImplementedError
  end

  # methods not so important yet : reset, power_on, power_off, transfer_protocol

#==============
#== messages ==
#==============

  # message format (hash)
  # message type + :payload = (array of paramerter type + :value)

  # create a message
  # - type : message id or name
  # - payload : array [parameter id or name, content]
  def create_message(type,payload=nil)

    # the type
    msg_type = nil
    if type.kind_of?(Fixnum) then
      msg_type = MESSAGES.collect{|x| x[:id]==type ? x : nil}.compact
    elsif type.kind_of?(String) then
      msg_type = MESSAGES.collect{|x| x[:name]==type ? x : nil}.compact
    else
      raise "unknown message type : #{type}"
    end
    raise "message type #{type} not found" unless msg_type.size==1
    message = msg_type[0].dup

    # the parameters
    message[:payload] = []
    payload = [] unless payload
    payload.each do |parameter|
      param_type = nil
      if parameter[0].kind_of?(Fixnum) then
        param_type = PARAMETERS.collect{|x| x[:id]==parameter[0] ? x : nil}.compact
      elsif parameter[0].kind_of?(String) then
        param_type = PARAMETERS.collect{|x| x[:name]==parameter[0] ? x : nil}.compact
      else
        raise "unknown parameter type : #{parameter[0]}"
      end
      raise "parameter type #{parameter[0]} not found" unless param_type.size==1
      # verify size of parameter
      raise "wrong parameter size #{parameter[1].size}" unless (param_type[0][:length]==-1 or param_type[0][:length]==parameter[1].size)
      param = param_type[0].dup
      param[:value] = parameter[1]
      message[:payload] << param
    end

    return message

  end

  # get binary representation of message
  def pack_message(message)

    # the binary array
    msg_bin = []
    msg_bin << message[:id]
    msg_bin << message[:payload].size%0xff
    msg_bin += [0,0]
    message[:payload].each do |parameter|
      msg_bin << parameter[:id]
      msg_bin << 0
      msg_bin << parameter[:value].size/0xff
      msg_bin << parameter[:value].size%0xff
      msg_bin += parameter[:value]
      msg_bin += [0]*(4-(1+1+2+parameter[:value].size)%4)
    end

    return msg_bin
  end

  # parse messages
  # input is @buffer_in (in byte array)
  # parsed messages are added to @messages_in
  def parse_messages

    log("parsing",hex(@buffer_in),4)
    # message header is requiered
    return if @buffer_in.length<4

    # get message_type from id
    msg_id = @buffer_in[0]
    msg_type = MESSAGES.collect{|x| x[:id]==msg_id ? x : nil}.compact
    raise "message type for id #{msg_id} not found" unless msg_type.size==1
    message = msg_type[0].dup

    # the number of parameters (+ verification)
    nb_param = @buffer_in[1]
    min_nb_param = message[:parameters].collect{|x| x[1] ? x : nil}.compact.size
    max_nb_param = message[:parameters].size
    raise "wrong number of parameters : #{nb_param} instead of #{min_nb_param}-#{max_nb_param}" if nb_param<min_nb_param or nb_param>max_nb_param

    # the reservered field
    log("parsing","reservered field in message used : (#{hex(@buffer_in[2,2])})",4) unless @buffer_in[2,2]==[0,0]

    # get each parameter
    message[:payload] = []
    seek = 4 # beginning of next parameter
    nb_param.times do
      # parameter header requiered
      return if @buffer_in.length<seek+4
      # get id then type
      param_id = @buffer_in[seek]
      param_type = PARAMETERS.collect{|x| x[:id]==param_id ? x : nil}.compact
      raise "parameter type for id #{param_id} not found" unless param_type.size==1
      parameter = param_type[0].dup
      # check reserved field
      log("parsing","reservered field in parameter used : #{hex(@buffer_in[seek+1,1])}",4) unless @buffer_in[seek+1]==0
      # get and check length
      param_length = (@buffer_in[seek+2]<<8)+@buffer_in[seek+3]
      raise "wrong parameter length : #{param_length} instead of #{parameter[:length]}" unless (parameter[:length]==-1 or parameter[:length]==param_length)
      # parameter value required
      return if @buffer_in.length<seek+4+param_length
      # get parameter value
      parameter[:value]=@buffer_in[seek+4,param_length]
      # verify padding
      padding_size = 4-((1+1+2+param_length)%4)
      # padding required
      return if @buffer_in.length<seek+4+param_length+padding_size
      padding=@buffer_in[seek+4+param_length,padding_size]
      raise "padding not empty : (#{padding_size}) #{hex(padding)}" unless padding.count{|x| x==0}==padding_size
      # next parameter
      message[:payload] << parameter
      seek += 1+1+2+param_length+padding_size
    end

    # print message
    log("parsed",hex(@buffer_in[0,seek]),4)
    print_message(message,true)
    # add message to message list
    @messages_in << message
    # get rid of the decoded data
    @buffer_in = @buffer_in[seek..-1]
    # get rest of the messages if there are any
    parse_messages if @buffer_in.size>0

  end
  
  # print the text message
  # - message : the message to print
  # - incoming : is message comming in (else going out)
  def print_message(message,incoming)
    log("msg #{incoming ? 'get' : 'send'}","#{incoming ? '>' : '<'} #{message[:name]} (#{hex(message[:id])})",4)
    message[:payload].each do |parameter|
      value = case parameter[:id]
      # get text value if possible
      when 0x01 # "ConnectionStatus"
        CONNECTION_STATUS[parameter[:value][0]] or "Reserved"
      when 0x02 # "ResultCode"
        RESULT_CODE[parameter[:value][0]] or "Reserved"
      when 0x08 # "StatusChange"
        STATUS_CHANGE[parameter[:value][0]] or "Reserved"
      else
        nil
      end
      if value then
        value += " (#{hex(parameter[:value])})"
      else
        value = hex(parameter[:value])
      end
      log("msg #{incoming ? 'get' : 'send'}","    #{parameter[:name]} (#{hex(parameter[:id])}) : #{value}",4)
    end
  end

  # send the message
  def send(message)

    # get binary
    msg_bin = pack_message(message)

    # check the size
    if msg_bin.size > @max_msg_size then
      raise "message size (#{msg_bin.size}) exceeds maximun (#{@max_msg_size})"
    end

    # print message
    print_message(message,false)
    log("IO","< (#{msg_bin.size}) #{hex(msg_bin)}",5)

    # send the message
    @io.write msg_bin.pack("C*")
    @io.flush

  end

#=========
#== log ==
#=========

  # verbosity
  # - 0 : nothing
  # - 1 : ATR/APDU (blue)
  # - 2 : state machine (yellow)
  # - 3 : inner task (green)
  # - 4 : messages (red)
  # - 5 : byte traffic
  VERBOSE = 5

  # for the logs
  def log (group,message,level)
    if @verbosity and @verbosity>=level then
      color = 95-level
      @verbose.puts "\e[1m\e[#{color}m[#{group}]\e[0m #{message}"
    end
  end

#===========
#== utils ==
#===========

  # return hex representation
  def hex(data)
    to_return = ""
    if data.kind_of?(Integer) then
      to_return = data.to_s(16).rjust(2,'0')
    elsif data.kind_of?(String) then
      to_return = hex(data.unpack("C*"))
    elsif data.kind_of?(Array) then
      to_return = data.collect{|x| x.to_s(16).rjust(2,'0')}*' '
    end
    return to_return
  end

end
