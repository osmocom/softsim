# encoding: UTF-8
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
# this is the client part of the SAP
# it implements the state machine for the client
require './sap/common.rb'

# this is an abstract class
# TODO :
# - verify state before sending
# - respect max size (and require min size)
# - ERROR_RESP handling
class Client < SAP

  # make the class abstract
  private :initialize
  
  def initialize(io)
    super(io)

    # state of the state machine
    @state = nil

    # initiate the state machine (connect_req)
    set_state :not_connected
    @max_msg_size = 0xffff

    # sim can be used
    @sim_ok = false
  end

  def start
    # start the client in another thread
    thread = Thread.new do
      super
    end
    thread.abort_on_exception = true
  end

  # add sim access protection
  def set_state (state)
    super(state)
    if @state==:not_connected or @state==:connection_under_negociation then
      @sim_ok = false
    end
  end

  # verify result code
  def result_ok?(message)
    # is it a ResultCode
    raise "message does not contains a result code" unless message[:payload][0][:id]==0x02
    if message[:payload][0][:value][0]==0x00 then
      return true
    else
      log("error","message result code : #{RESULT_CODE[message[:payload][0][:value][0]]}",1)
      return false
    end
  end

  def state_machine(message)
    # check direction
    raise "got client to server message" unless message[:server_to_client]
    case message[:name]
    when "CONNECT_RESP"
      raise "msg #{message[:name]} in wrong state : #{@state}" unless @state==:connection_under_negociation
      connection_status = message[:payload][0][:value][0]
      max_msg_size = nil
      # print response
      if message[:payload].size == 1 then
        log("client","connection : #{CONNECTION_STATUS[connection_status]}",3)
      elsif message[:payload].size == 2 then
        max_msg_size = (message[:payload][1][:value][0]<<8)+message[:payload][1][:value][1]
        log("client","connection : #{CONNECTION_STATUS[connection_status]} (max message size = #{max_msg_size})",3)
      end
      # verify response
      if connection_status==0x00 then
        # OK, Server can fulfill requirements
        log("client","connected to server",3)
        set_state :idle
      elsif connection_status==0x02 and message[:payload].size==2 then
        # Error, Server does not support maximum message size
        log("client","server can not handle size. adapting",3)
        @max_msg_size = max_msg_size
        set_state :not_connected
      else
        set_state :not_connected
        raise "connection error"
      end
    when "DISCONNECT_RESP"
      log("client","disconnected",3)
      set_state :not_connected
      @end=true
    when "STATUS_IND"
      status = message[:payload][0][:value][0]
      log("client","new card status : #{STATUS_CHANGE[status]}",3)
      if status==0x01 then
        # card reset
        @sim_ok = true
      else
        @sim_ok = false
      end
    when "TRANSFER_ATR_RESP"
      raise "msg #{message[:name]} in wrong state : #{@state}" unless @state==:processing_atr_request
      if result_ok?(message) then
        @atr = message[:payload][1][:value]
      else
        #TODO : raise error, or retry later ?
      end
      set_state :idle
    when "TRANSFER_APDU_RESP"
      raise "msg #{message[:name]} in wrong state : #{@state}" unless @state==:processing_apdu_request
      if result_ok?(message) then
        @apdu = message[:payload][1][:value]
      else
        #TODO : raise error, or retry later ?
      end
      set_state :idle
    when "ERROR_RESP"
      log("error","got an error response",1)
      if @state==:connection_under_negociation then
        set_state :not_connected
      elsif @state!=:not_connected and @state!=:idle then
        set_state :idle
      end
    else
      raise "not implemented or unknown message type : #{message[:name]}"
    end
  end

  def connect
    log("client","connecting",3)
    # wait to be connected
    until @state==:idle do
      if @state == :not_connected then
        payload = []
        # ["MaxMsgSize",[size]]
        payload << [0x00,[(@max_msg_size>>8)&0xff,@max_msg_size&0xff]]
        connect = create_message("CONNECT_REQ",payload)
        send(connect)
        set_state :connection_under_negociation
      elsif @state!=:connection_under_negociation and @state!=:idle
        raise "can not connect. required state : not_connected, current state : #{@state}"
        return false
      end
    end
    # wait for the sim to be ready
    until @sim_ok do
      sleep @wait_time
    end
    return true
  end

  def disconnect
    log("client","disconnecting",3)
    if @state==:not_connected or @state==:connection_under_negociation then
      raise "can not disconnect. must be connected, current state : #{@state}"
      return false
    else # send DISCONNECT_REQ
      connect = create_message("DISCONNECT_REQ")
      send(connect)
      until @state==:not_connected
        sleep @wait_time
      end
      return true
    end
  end
  
  # return ATR (byte array)
  def atr
    if @state==:idle then
      connect = create_message("TRANSFER_ATR_REQ")
      send(connect)
      set_state :processing_atr_request
      # wait for the ATR
      until @state==:idle
        sleep @wait_time
      end
      log("ATR","#{hex(@atr)}",1)
      return @atr
    else
      raise "can not ask ATR. must be  in state idle, current state : #{@state}"
      return nil
    end
  end

  # return the response of the apdu request
  def apdu(request)
    raise "APDU request empty" unless request and request.size>=5
    log("APDU","< #{hex(request)}",1)
    if @state==:idle then
      # ["CommandAPDU",[apdu]]
      connect = create_message("TRANSFER_APDU_REQ",[[0x04,request]])
      send(connect)
      set_state :processing_apdu_request
      # wait for the ATR
      until @state==:idle
        sleep @wait_time
      end
      log("APDU","> #{hex(@apdu)}",1)
      return @apdu
    else
      raise "can not sen APDU request. must be  in state idle, current state : #{@state}"
      return nil
    end
  end
end
