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

_addon.name = 'fisher'
_addon.version = '1.0.0'
_addon.command = 'fisher'
_addon.author = 'Seth VanHeulen'

catch_id = '\13\0\228\2'
catch_key = nil
catch_delay = 20
catch_time = nil
cast_delay = 3
cast_time = nil
running = false

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running == true then
        if id == 0x115 then
            if catch_id == original:sub(11, 14) then
                catch_key = original:sub(21)
                catch_time = os.time() + catch_delay
            else
                player = windower.ffxi.get_player()
                payload = '\16\11\0\0' .. string.char(player.id % 256, player.id / 256) .. '\0\0\200\0\0\0' .. string.char(player.index % 256, player.index / 256) .. '\3\0\0\0\0\0'
                windower.packets.inject_outgoing(0x110, payload)
            end
        elseif id == 0x53 then
            cast_delay = cast_delay + 1
            cast_time = os.time() + 2
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running == true and id == 0x110 and original:byte(15) == 4 then
        cast_time = os.time() + cast_delay
    end
end

function check_prerender()
    if catch_time ~= nil and os.time() >= catch_time then
        catch_time = nil
        player = windower.ffxi.get_player()
        payload = '\16\11\0\0' .. string.char(player.id % 256, player.id / 256) .. '\0\0\0\0\0\0' .. string.char(player.index % 256, player.index / 256) .. '\3\0' .. catch_key
        windower.packets.inject_outgoing(0x110, payload)
    elseif cast_time ~= nil and os.time() >= cast_time then
        cast_time = nil
        windower.send_command('input /fish')
    end
end

function fisher_command(...)
    if #arg == 1 and arg[1]:lower() == 'stop' then
        catch_time = nil
        cast_time = nil
        running = false
    elseif #arg == 1 and arg[1]:lower() == 'start' then
        cast_time = os.time()
        running = true
    end
end

windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('prerender', check_prerender)
windower.register_event('addon command', fisher_command)
