# this is the client part of the SAP
# it implements the state machine for the client
require 'common'

# this is an bastract class
# to implement : connect,disconnect,reset,atr,apdu
class Client < SAP

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
    connect()
    super
  end

  def state_machine(message)
    # check direction
    raise "got client to server message" unless message[:server_to_client]
    case message[:name]
    when "CONNECT_RESP"
      connection_status = message[:payload][0][:value][0]
      # print response
      if message[:payload].size == 1 then
        log("client","connection : #{SAP::CONNECTION_STATUS[connection_status]}",3)
      else
        @max_msg_size = (message[:payload][1][:value][0]<<8)+message[:payload][1][:value][1]
        log("client","connection : #{SAP::CONNECTION_STATUS[connection_status]} (max message size = #{@max_msg_size})",3)
      end
      # verify response
      if connection_status==0 and message[:payload].size==2 then # OK
        set_state :idle
      else
        set_state :not_connected
        raise "connection error"
      end
    when "STATUS_IND"

      # save status change
      @status = message[:parameters][0][:value][0]
      @verbose.puts "new status : #{SAP::STATUS_CHANGE[@status]}"
      @state = :idle

      # if SIM reseted, ask for ATR
      if @status == SAP::STATUS_CHANGE.index("Card reset") then
        get_atr
      end

    when "ERROR_RESP"
      case @state
      when :connection_under_negociation
        @case = :not_connected
      else
        @state = :idle
      end
    when "TRANSFER_ATR_RESP"
      result = message[:parameters][0][:value][0]
      @verbose.puts SAP::RESULT_CODE[result]
      if result == SAP::RESULT_CODE.index("OK, request processed correctly") then
        atr = message[:parameters][1][:value]
        @verbose.puts atr.collect{|x| x.to_s(16).rjust(2,'0')}*' '
      end
      @state = :idle
    else
      raise "not implemented or unknown message type : #{message[:name]}"
    end
  end

  # send CONNECT_REQ
  def connect
    log("client","connecting",3)
    if @state == :not_connected then
      connect = create_message("CONNECT_REQ",[["MaxMsgSize",[(@max_msg_size>>8)&0xff,@max_msg_size&0xff]]])
      send(connect)
      @state = :connection_under_negociation
    else
      @io.close
      raise "can not connect. required state : not_connected, current state : #{@state}"
    end
  end

  # send TRANSFER_ATR_REQ
  def get_atr
    if @state == :idle then
      connect = create_message("TRANSFER_ATR_REQ",[])
      send(connect)
      @state = :processing_atr_request
    else
      @sap.close
      raise "can request ATR. required state : idle, current state : #{@sate}"
    end
  end
  
end