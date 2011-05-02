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

# transform binary string into readable hex string
class String
  def to_hex_disp
    to_return = ""
    each_byte do |b|
      to_return += b.to_s(16).rjust(2,"0")
      to_return += " "
    end
    return to_return[0..-2].upcase
  end

  def to_hex
    to_return = ""
    each_byte do |b|
      to_return += b.to_s(16).rjust(2,"0")
    end
    #to_return = "0x"+to_return
    return to_return.downcase
  end
  
  # convert a hexadecimal string into binary array
  def hex2arr
    arr = []
    (self.length/2).times do |i|
      arr << self[i*2,2].to_i(16)
    end
    return arr
  end
end

# reverse the nibbles of each byte
class Array
  # print the nibbles (often BCD)
  # - padding : the 0xf can be ignored (used as padding in BCD)
  def nibble_str(padding=false)
    # get nibble representation
    to_return = collect { |b| (b&0x0F).to_s(16)+(b>>4).to_s(16) }
    to_return = to_return.join
    # remove the padding
    to_return.gsub!('f',"") if padding
    return to_return
  end

  def to_hex_disp
    to_return = ""
    each do |b|
      to_return += b.to_s(16).rjust(2,"0")
      to_return += " "
    end
    return to_return[0..-2].upcase
  end

  def to_hex
    to_return = ""
    each do |b|
      to_return += b.to_s(16).rjust(2,"0")
    end
    #to_return = "0x"+to_return
    return to_return.downcase
  end
end
