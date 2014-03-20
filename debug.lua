--[[
Copyright 2014 Seth VanHeulen

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

_addon.name = 'debug'
_addon.version = '1.0.0'
_addon.command = 'debug'
_addon.author = 'Seth VanHeulen'

function string.tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if id == 0x115 then
        windower.add_to_chat(167, 'incoming: ' .. string.tohex(original))
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if id == 0x110 then
        windower.add_to_chat(167, 'outgoing: ' .. string.tohex(original))
    end
end

windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
