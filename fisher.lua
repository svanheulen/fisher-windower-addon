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
_addon.version = '1.1.3'
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

-- binary helper functions

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
    if items.equipment.ammo == 0 or items.inventory[items.equipment.ammo].id ~= bait_id then
        return false
    end
    return true
end

function equip_bait()
    for slot,item in pairs(windower.ffxi.get_items().inventory) do
        if item.id == bait_id and item.status == 0 then
            windower.ffxi.set_equip(slot, 3)
            return true
        end
    end
    return false
end

-- inventory helper functions

function check_inventory()
    local count = 0
    local items = windower.ffxi.get_items()
    for _,item in pairs(items.inventory) do
        if item.id ~= 0 then
            count = count + 1
        end
    end
    return count < items.max_inventory
end

-- event callback functions

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running and id == 0x115 then
        if fish_id == original:sub(11, 14) then
            catch_key = original:sub(21)
            catch_time = os.time() + catch_delay
        else
            release_time = os.time() + release_delay
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running and id == 0x110 and original:byte(15) == 4 then
        cast_time = os.time() + cast_delay
    end
end

function check_prerender()
    if running then
        if catch_time ~= nil and os.time() >= catch_time then
            catch_time = nil
            local player = windower.ffxi.get_player()
            windower.packets.inject_outgoing(0x110, '\16\11\0\0' .. pack_uint32(player.id) .. '\0\0\0\0' .. pack_uint16(player.index) .. '\3\0' .. catch_key)
        elseif release_time ~= nil and os.time() >= release_time then
            release_time = nil
            local player = windower.ffxi.get_player()
            windower.packets.inject_outgoing(0x110, '\16\11\0\0' .. pack_uint32(player.id) .. '\200\0\0\0' .. pack_uint16(player.index) .. '\3\0\0\0\0\0')
        elseif cast_time ~= nil and os.time() >= cast_time then
            cast_time = nil
            if check_inventory() then
                if check_bait() then
                    windower.send_command('input /fish')
                elseif equip_bait() then
                    cast_time = os.time() + cast_delay
                end
            end
        end
    end
end

function fisher_command(...)
    if #arg == 1 and arg[1]:lower() == 'stop' then
        catch_time = nil
        release_time = nil
        cast_time = nil
        running = false
    elseif #arg == 1 and arg[1]:lower() == 'start' then
        catch_time = nil
        release_time = nil
        cast_time = os.time()
        running = true
    end
end

-- register event callbacks

windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('prerender', check_prerender)
windower.register_event('addon command', fisher_command)
