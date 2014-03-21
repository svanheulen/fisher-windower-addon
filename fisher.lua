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
_addon.version = '1.2.0'
_addon.command = 'fisher'
_addon.author = 'Seth VanHeulen'

bait_id = 17400 -- sinking minnow
fish_id = '\13\0\228\2' -- hakuryu
catch_key = nil
catch_delay = 20
catch_time = nil
release_delay = 1
release_time = nil
cast_delay = 4
cast_time = nil
running = false
log_file = nil
log_level = -1
chat_level = 0

-- debug and logging functions

function message(level, message)
    if log_level >= level then
        log_file:write(os.time(), message)
        log_file:flush()
    end
    if chat_level >= level then
        local color = 167
        if level == 1 then
            color = 207
        elseif level == 2 then
            color = 160
        end
        windower.add_to_chat(color, message)
    end
end

-- binary helper functions

function string.tohex(str)
    return str:gsub('.', function (c) return '%02X':format(string.byte(c)) end)
end

function pack_uint16(num)
    return string.char(num % 0x100, math.floor(num / 0x100))
end

function pack_uint32(num)
    local str = string.char(num % 0x100)
    str = str .. string.char(math.floor(num / 0x100) % 0x100)
    str = str .. string.char(math.floor(num / 0x10000) % 0x100)
    return str .. string.char(math.floor(num / 0x1000000))
end

-- bait helper functions

function check_bait()
    local items = windower.ffxi.get_items()
    message(1, 'checking equiped bait: %d':format(bait_id))
    return items.equipment.ammo ~= 0 and items.inventory[items.equipment.ammo].id == bait_id
end

function equip_bait()
    for slot,item in pairs(windower.ffxi.get_items().inventory) do
        if item.id == bait_id and item.status == 0 then
            message(1, 'equiping bait: %d, from slot: %d':format(bait_id, slot))
            windower.ffxi.set_equip(slot, 3)
            return true
        end
    end
    message(0, 'out of bait: %d':format(bait_id))
    fisher_command('stop')
    return false
end

-- inventory helper functions

function check_inventory()
    local count = 0
    local items = windower.ffxi.get_items()
    message(1, 'checking inventory space')
    for _,item in pairs(items.inventory) do
        if item.id ~= 0 then
            count = count + 1
        end
    end
    if count == items.max_inventory then
        message(0, 'inventory full')
        fisher_command('stop')
        return false
    end
    return true
end

-- event callback functions

function check_chat_message(message, sender, mode, gm)
    if gm then
        message(0, 'incoming gm chat')
        fisher_command('stop')
    end
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running and id == 0x115 then
        message(2, 'incoming fish info: ' .. original:tohex())
        if fish_id == original:sub(11, 14) then
            catch_key = original:sub(21)
            message(1, 'catching fish in %d seconds':format(catch_delay))
            catch_time = os.time() + catch_delay
        else
            message(1, 'releasing fish in %d seconds':format(release_delay))
            release_time = os.time() + release_delay
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running and id == 0x110 then
        message(2, 'outgoing fishing action: ' .. original:tohex())
        if original:byte(15) == 4 then
            message(1, 'casting in %d seconds':format(cast_delay))
            cast_time = os.time() + cast_delay
        end
    end
end

function check_prerender()
    if running then
        if catch_time ~= nil and os.time() >= catch_time then
            catch_time = nil
            local player = windower.ffxi.get_player()
            message(1, 'catching fish')
            windower.packets.inject_outgoing(0x110, '\16\11\0\0' .. pack_uint32(player.id) .. '\0\0\0\0' .. pack_uint16(player.index) .. '\3\0' .. catch_key)
        elseif release_time ~= nil and os.time() >= release_time then
            release_time = nil
            local player = windower.ffxi.get_player()
            message(1, 'releasing fish')
            windower.packets.inject_outgoing(0x110, '\16\11\0\0' .. pack_uint32(player.id) .. '\200\0\0\0' .. pack_uint16(player.index) .. '\3\0\0\0\0\0')
        elseif cast_time ~= nil and os.time() >= cast_time then
            cast_time = nil
            if check_inventory() then
                if check_bait() then
                    message(1, 'casting')
                    windower.send_command('input /fish')
                elseif equip_bait() then
                    message(1, 'casting in %d seconds':format(cast_delay))
                    cast_time = os.time() + cast_delay
                end
            end
        end
    end
end

function fisher_command(...)
    if #arg == 1 and arg[1]:lower() == 'stop' then
        message(1, 'stopped fishing')
        catch_time = nil
        release_time = nil
        cast_time = nil
        running = false
    elseif #arg == 1 and arg[1]:lower() == 'start' then
        message(1, 'started fishing')
        catch_time = nil
        release_time = nil
        cast_time = os.time()
        running = true
    end
end

-- register event callbacks

windower.register_event('chat message', check_chat_message)
windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('prerender', check_prerender)
windower.register_event('addon command', fisher_command)
