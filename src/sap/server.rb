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
# this is the server part of the SAP
# it implements the state machine for the server
# this is an abstract class
require 'sap/common'

# this is an bastract class
# TODO (not implemented) :
# - respect max message size (and check minimum)
# - refuse connection if card is missing
# - server initiated disconnect (when programm want to exit or card is lost)
# - transport protocol change
# - power sim on/off or reset
# - ERROR_RESP sending (instead of exception)
class Server < SAP

  # make the class abstract
  private :initialize

  # create the SAP server

  def initialize(io)
    super(io)

    # for the server inifinite loop
    @end = false
    # state of the state machine
    @state = nil

    # open socket to listien to
    log("server","created",3)

    # initiate the state machine (connect_req)
    set_state :not_connected
    @max_msg_size = 0xffff

  end

  # implementing state machine (SAP figure 4.13)
  def state_machine(message)
      # check direction
      raise "got server to client message" unless message[:client_to_server]
      case message[:name]
      when "CONNECT_REQ"
        raise "msg #{message[:name]} in wrong state #{@state}" unless @state==:not_connected
        set_state :connection_under_nogiciation
        # get client max message size
        max_msg_size = (message[:payload][0][:value][0]<<8)+message[:payload][0][:value][1]
        log("server","incoming connection request (max message size = #{max_msg_size})",3)
        # negociate MaxMsgSize
        if max_msg_size>@max_msg_size then
          # send my max size
          # connection response message
          payload = []
          # ["ConnectionStatus",["Error, Server does not support maximum message size"]]
          payload << [0x01,[0x02]]
          # ["MaxMsgSize",[size]]
          payload << [0x00,[@max_msg_size>>8,@max_msg_size&0xff]]
          # send response
          response = create_message("CONNECT_RESP",payload)
          send(response)
          set_state :not_connected
          log("server","connection refused",3)
        else
          # accept the value
          @max_msg_size = max_msg_size
          # connection response message
          payload = []
          # ["ConnectionStatus",["OK, Server can fulfill requirements"]]
          payload << [0x01,[0x00]]
          # ["MaxMsgSize",[size]]
          payload << [0x00,[@max_msg_size>>8,@max_msg_size&0xff]]
          # send response
          response = create_message("CONNECT_RESP",payload)
          send(response)
          set_state :idle
          log("server","connection established",3)
          # try to connect until connected
          until connect() do
            # ["StatusChange",["Card not accessible"]]
            status = create_message("STATUS_IND",[[0x08,[0x02]]])
            send(status)
            sleep 1
          end
          # card ready
          # ["StatusChange",["Card reset"]]
          status = create_message("STATUS_IND",[[0x08,[0x01]]])
          send(status)
          log("server","card ready",3)
        end
      when "DISCONNECT_REQ"
        raise "msg #{message[:name]} in wrong state #{@state}" unless @state!=:not_connected and @state!=:connection_under_nogiciation
        log("server","client disconneting",3)
        disconnect()
        response = create_message("DISCONNECT_RESP")
        send(response)
        set_state :not_connected
      when "TRANSFER_ATR_REQ"
        raise "msg #{message[:name]} in wrong state #{@state}" unless @state==:idle
        set_state :processing_atr_request
        # atr should return ATR byte array, nil if not available
        atr_result = atr
        payload = []
        if atr_result then
          log("ATR","#{hex(atr_result)}",1)
          # ["ResultCode",["OK, request processed correctly"]]
          payload << [0x02,[0x00]]
          # ["ATR",atr]
          payload << [0x06,atr_result]
        else
          # ["ResultCode",["Error, data not available"]]
          payload << [0x02,[0x06]]
        end
        # send response
        response = create_message("TRANSFER_ATR_RESP",payload)
        send(response)
        set_state :idle
      when "TRANSFER_APDU_REQ"
        raise "msg #{message[:name]} in wrong state #{@state}" unless @state==:idle
        set_state :processing_apdu_request
        # apdu should return APDU response byte array, or error result code
        raise "no APDU request in message" unless message[:payload].size==1
        log("APDU","> #{hex(message[:payload][0][:value])}",1)
        apdu_result = apdu(message[:payload][0][:value])
        log("APDU","< #{hex(apdu_result)}",1)
        payload = []
        if apdu_result.kind_of?(Array) then
          # ["ResultCode",["OK, request processed correctly"]]
          payload << [0x02,[0x00]]
          # ["ResponseAPDU",apdu]
          payload << [0x05,apdu_result]
        elsif atr_result.kind_of?(Integer) then
          # ["ResultCode",[code from atr]]
          payload << [0x02,[apdu_result]]
        else
          raise "unexpected answer #{atr_result.class} from atr"
        end
        # send response
        response = create_message("TRANSFER_APDU_RESP",payload)
        send(response)
        set_state :idle
      else
        raise "not implemented or unknown message type : #{message[:name]}"
      end
  end

end
