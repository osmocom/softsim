#!/usr/bin/env ruby
require 'client'
#sudo aptitude install libdbus-ruby
require 'dbus'

# class to connect to BT SAP server using BlueZ over dbus
class BluetoothClient < File

  # bluetooth SAP UUID
  SAP_UUID = "0000112d-0000-1000-8000-00805f9b34fb"
  SAP = SAP_UUID[4,4]
  # scan duration in s
  SCAN_DURATION = 5

  def initialize
    
    @bt_service = BluetoothClient.service()
    @bt_manager = BluetoothClient.manager(@bt_service)
    @bt_adapter = BluetoothClient.adapter(@bt_service,@bt_manager)
    @bt_device_addr = BluetoothClient.device(@bt_service,@bt_adapter)
    connect() # also creates @rfcomm

    super(@rfcomm,"r+")
  end

  # get bluetooth service
  # setting up the bluetooth
  def self.service
    # bluetooth is on the system dbus
    bus = DBus::SystemBus.instance
    # the bluetooth service is provided by Bluez
    bt_service = bus.service("org.bluez")

    return bt_service
  end

  # get bt_manager
  # needs a service
  def self.manager (bt_service)
    # the main object is /
    bt_manager = bt_service.object("/")
    # load the methods
    bt_manager.introspect
    # get the rigth interface for the manager
    bt_manager.default_iface = "org.bluez.Manager"

    return bt_manager
  end

  # get bt adapter
  # needs a service and manager
  def self.adapter (bt_service,bt_manager)
    # list adapters
    bt_adapter_list = bt_manager.ListAdapters()[0]
    bt_adapter_default = bt_manager.DefaultAdapter()[0]
    # get information about adapters
    bt_adapters = []
    bt_adapter_list.each do |adapter|
      bt_adapter = bt_service.object(adapter)
      bt_adapter.introspect
      bt_adapter.default_iface = "org.bluez.Adapter"
      #$stdout.puts bt_abapter_object["org.bluez.Adapter"].Address
      bt_adapter = bt_adapter.GetProperties()[0]
      bt_adapters << {
        :object => adapter,
        :name => bt_adapter["Name"],
        :address => bt_adapter["Address"],
        :adapter => adapter.split('/')[-1],
        :default => adapter==bt_adapter_default
      }
    end

    # select adapter
    if bt_adapters.size==0 then
      raise "no Bluetooth adapter available"
    elsif bt_adapters.size==1 then
      bt_adapter = bt_adapters[0]
    else
      $stdout.puts "multiple bluetooth adapter "
      bt_adapters.each_index do |i|
        bt_adapter = bt_adapters[i]
        $stdout.puts "#{i}) #{bt_adapter[:adapter]} (#{bt_adapter[:address]} - #{bt_adapter[:name]})#{bt_adapter[:default] ? ' [default]' : ''}"
      end
      $stdout.print "select adapter : "
      adapter = $stdin.gets.chomp
      if adapter.length==0 then
        bt_adapters.each_index do |i|
          if bt_adapters[i][:default] then
            bt_adapter = bt_adapters[i]
          end
        end
      else
        bt_adapter = bt_adapters[adapter.to_i]
      end
    end
    $stdout.puts "using adapter #{bt_adapter[:adapter]} (#{bt_adapter[:address]} - #{bt_adapter[:name]})"

    # getting adapter
    bt_adapter = bt_service.object(bt_adapter[:object])
    bt_adapter.introspect
    bt_adapter.default_iface = "org.bluez.Adapter"

    return bt_adapter
  end

  # get bt device addr with SAP
  # needs a service and adapter
  def self.device (bt_service,bt_adapter)
    
    # discovering devices

    # remenber discovered devices (sort of thread)
    devices = {}
    bt_adapter.on_signal("DeviceFound") do |address,properties|
        devices[address]=properties
    end

    # scan for devices
    $stdout.puts "scanning for #{SCAN_DURATION} seconds"
    bt_adapter.RequestSession()
    bt_adapter.StartDiscovery()
    sleep SCAN_DURATION
    bt_adapter.StopDiscovery()
    bt_adapter.ReleaseSession()

    # list found devices
    if devices.size==0 then
      puts "no devices found"
      exit 0
    end
    $stdout.puts "#{devices.size} device(s) found :"
    devices.each do |address,properties|
      $stdout.puts "- #{properties["Name"]} (#{properties["Address"]})"
    end

    # check for SAP
    $stdout.puts "SAP existing ? :"
    sap_devices = []
    devices.each do |address,properties|

      # verify if the device already exists
      device_object = "dev_"+properties["Address"].gsub(/:/,"_")
      device_exists = false
      bt_adapter.subnodes.each do |device|
        device_exists = true if device == device_object
      end
      # get the device (create it if it does not exist)
      if !device_exists then
        device_object = bt_adapter.CreateDevice(properties["Address"])[0]
      else
        device_object = bt_adapter.path+"/"+device_object
      end

      # get the device
      bt_device = bt_service.object(device_object)
      bt_device.introspect
      bt_device.default_iface = "org.bluez.Device"

      # find SAP in the UUIDs
      sap = false
      bt_device.GetProperties()[0]["UUIDs"].each do |uuid|
        sap = true if uuid[4,4]==SAP
      end
      $stdout.puts "- #{properties["Name"]} (#{properties["Address"]}) #{sap ? 'has' : 'has no'} SAP"

      # remember device if it has SAP
      sap_devices << { :name => properties["Name"] , :addr => properties["Address"]} if sap

      # remove created object
      bt_adapter.RemoveDevice(device_object) unless properties["Paired"] or properties["Trusted"]

    end

    # select SAP device to use
    if sap_devices.size == 0 then
      $stderr.puts "no SAP devices found"
      exit 1
    elsif sap_devices.size == 1 then
      sap_device = sap_devices[0]
    else
      $stdout.puts "multiple devices possible"
      sap_devices.each_index do |i|
        $stdout.puts "-  #{sap_devices[0][:name]} (#{sap_devices[0][:addr]}"
      end
      $stdout.print "select device : "
      sap_device = $stdin.gets.chomp
      sap_device = sap_devices[sap_device]
    end
    $stdout.puts "using device #{sap_device[:name]} (#{sap_device[:addr]})"

    return sap_device[:addr]
  end

  # connet to device (get rfcomm)
  def connect

    # verify if the device already exists
    sap_object = "dev_"+@bt_device_addr.gsub(/:/,"_")
    sap_exists = false
    @bt_adapter.subnodes.each do |device|
      sap_exists = true if device == sap_object
    end
    # get the device (create it if it does not exist)
    if !sap_exists then
      sap_object = @bt_adapter.CreateDevice(@bt_device_addr)[0]
    else
      sap_object = @bt_adapter.path+"/"+sap_object
    end

    # create device
    @bt_sap = @bt_service.object(sap_object)
    @bt_sap.introspect

    # is it paired ?
    @bt_sap.default_iface = "org.bluez.Device"
    @paired = @bt_sap.GetProperties()[0]["Paired"]
    unless @paired then
      $stdout.puts "enter PIN (16 digits) on the device, then confirm it on the computer"
    end

    # connect to device
    @bt_sap.default_iface = "org.bluez.Serial"
    begin
      @rfcomm = @bt_sap.Connect(SAP_UUID)[0]
    rescue DBus::Error => e
      if e.to_s == "org.bluez.Error.Failed: Connection refused (111)" then
        $stderr.puts "Connection to device failed. Restarting the device might help"
        exit 1
      elsif e.to_s == "org.bluez.Error.Failed: Connection timed out" then
        $stderr.puts "Device does not respond to connection request"
        exit 1
      else
        raise
      end
    end

    @bt_sap.default_iface = "org.bluez.Device"
    @paired = @bt_sap.GetProperties()[0]["Paired"]
    @trusted = @bt_sap.GetProperties()[0]["Trusted"]

  end

  def close()
    # close file
    super

    @bt_sap.default_iface = "org.bluez.Serial"
    #disconnect the serial port
    @bt_sap.Disconnect(@rfcomm)
    # remove device
    @bt_adapter.RemoveDevice(@bt_sap.path) unless @trusted or @paired
  end

end

# demo application, using BT
io = BluetoothClient.new
client = Client.new(io)
client.start
client.connect
atr = client.atr
puts atr ? "ATR : #{atr.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get ATR"
# select MF
apdu_req = [0xA0,0xA4,0x00,0x00,0x02,0x3F,0x00]
puts "APDU request : #{apdu_req.collect{|x| x.to_s(16).rjust(2,'0')}*' '}"
apdu_resp = client.apdu(apdu_req)
puts apdu_resp ? "APDU response : #{apdu_resp.collect{|x| x.to_s(16).rjust(2,'0')}*' '}" :  "could not get APDu response"
client.disconnect
io.close