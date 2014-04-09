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

-- addon information

_addon.name = 'manualfisher'
_addon.version = '1.0.0'
_addon.command = 'manualfisher'
_addon.author = 'Seth VanHeulen'

-- modules

require('pack')

-- event callback functions

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running and id == 0x115 then
        windower.send_command('timers c "Fish On Line" 60')
        windower.add_to_chat(167, "fish bite id: '\\%d\\%d\\%d\\%d'":format(original:byte(11, 14)))
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running and id == 0x110 and original:byte(15) == 3 then
        windower.send_command('timers d "Fish On Line"')
        if original:unpack('I', 17) ~= 0 then
            return modified:sub(1, 8) .. '\0\0\0\0' .. modified:sub(13)
        end
    end
end

function fisher_command(...)
    if #arg == 1 and arg[1]:lower() == 'on' then
        running = true
        windower.add_to_chat(167, 'manualfisher: on')
    elseif #arg == 1 and arg[1]:lower() == 'off' then
        running = false
        windower.add_to_chat(167, 'manualfisher: off')
    else
        windower.add_to_chat(167, 'usage: manualfisher on')
        windower.add_to_chat(167, '        manualfisher off')
    end
end

-- register event callbacks

windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('addon command', fisher_command)
