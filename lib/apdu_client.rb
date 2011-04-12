#!/usr/bin/env ruby
# This programm will forward APDU from a TCP port to a SAP server
require 'socket'
require 'client'

SAP_HOST = "localhost"
SAP_PORT = "1337"
APDU_HOST = "localhost"
APDU_PORT = "1338"

# wait for a client to connect
socket = TCPServer.new(APDU_HOST,APDU_PORT)
io = socket.accept

# create SAP client to SAP server
sap = TCPSocket.open(SAP_HOST,SAP_PORT)
client = Client.new(sap,0)
client.start
client.connect
atr = client.atr
puts atr ? "ATR : #{atr.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get ATR"

@end = false
until @end do
  activity = IO.select([io])
  begin
    input = activity[0][0].readpartial(0xffff)
    req = input.unpack("C*")
    puts "> #{req.collect{|x| x.to_s(16).rjust(2,'0')}*' '}"
    resp = client.apdu(req)
    puts "< #{resp.collect{|x| x.to_s(16).rjust(2,'0')}*' '}"
    io.puts resp.pack("C*")
  rescue EOFError,Errno::EPIPE
    $stderr.puts "source disconnected"
    @end = true
  end
end

io.close
client.disconnect
sap.close