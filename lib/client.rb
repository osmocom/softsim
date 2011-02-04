# this is the client part of the SAP
# it implements the state machine for the client
require 'common'

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
    
  end

  def start
    # start the client in another thread
    thread = Thread.new do
      super
    end
    thread.abort_on_exception = true
  end

  def state_machine(message)
    # check direction
    raise "got client to server message" unless message[:server_to_client]
    case message[:name]
    when "CONNECT_RESP"
      connection_status = message[:payload][0][:value][0]
      max_msg_size = (message[:payload][1][:value][0]<<8)+message[:payload][1][:value][1]
      # print response
      if message[:payload].size == 1 then
        log("client","connection : #{SAP::CONNECTION_STATUS[connection_status]}",3)
      else
        log("client","connection : #{SAP::CONNECTION_STATUS[connection_status]} (max message size = #{@max_msg_size})",3)
      end
      # verify response
      if connection_status==0x00 and message[:payload].size==2 then
        # OK, Server can fulfill requirements
        log("client","connected",3)
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
    else
      raise "not implemented or unknown message type : #{message[:name]}"
    end
  end

  def connect
    log("client","connecting",3)
    until @state==:idle do
      if @state == :not_connected then
        payload = []
        # ["MaxMsgSize",[size]]
        payload << [0x00,[(@max_msg_size>>8)&0xff,@max_msg_size&0xff]]
        connect = create_message("CONNECT_REQ",payload)
        send(connect)
        set_state :connection_under_negociation
      elsif @state!=:connection_under_negociation
        raise "can not connect. required state : not_connected, current state : #{@state}"
        return false
      end
      sleep 0.1
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
        sleep 0.1
      end
      return true
    end
  end
  
end