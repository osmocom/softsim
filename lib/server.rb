#!/usr/bin/env ruby
# this is the server part of the SAP
require 'common'
require 'socket'

# TODO : respect max message size (SAP chapter 4.1.1)
class Server < SAP


  def initialize
    super

    @end = false
    @state = nil

    # open socket to listien to
    log("server","listening",3)
    @server = TCPServer.new("localhost",1234)
    @socket = @server.accept

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
        @max_msg_size = message[:payload][0][:value][0]<<8+message[:payload][0][:value][1]
        log("server","incoming connection request (size=#{hex(@max_msg_size)})",3)
        # commection response message
        payload = []
        payload << ["ConnectionStatus",[0x00]]
        payload << ["MaxMsgSize",message[:payload][0][:value]]
        response = create_message("CONNECT_RESP",payload)
        send(response)
        set_state :idle
        log("server","connection established",3)
      when "STATUS_IND"
      else
        raise "not implemented or unknown message type : #{message[:name]}"
      end
  end

end

# test application
main = Server.new
main.start