# this is the server part of the SAP
# it implements the state machine for the server
# this is an abstract class
require 'common'

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
          # send status
          payload = []
          # ["StatusChange",["Card reset"]]
          payload << [0x08,[0x01]]
          response = create_message("STATUS_IND",payload)
          send(response)
          log("server","SIM ready (reset)",3)
        end
      when "DISCONNECT_REQ"
          log("server","client disconneting",3)
          response = create_message("DISCONNECT_RESP")
          send(response)
          set_state :not_connected
      else
        raise "not implemented or unknown message type : #{message[:name]}"
      end
  end

end