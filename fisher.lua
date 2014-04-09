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

_addon.name = 'fisher'
_addon.version = '2.0.0'
_addon.command = 'fisher'
_addon.author = 'Seth VanHeulen'

-- modules

config = require('config')
require('pack')

-- default settings

defaults = {}
defaults.chat = 1
defaults.log = -1
defaults.equip = false
defaults.move = false
defaults.delay = {}
defaults.delay.release = 1
defaults.delay.cast = 4
defaults.delay.equip = 2
defaults.delay.move = 2
defaults.fatigue = {}
defaults.fatigue.date = os.date('!%Y-%m-%d', os.time() + 32400)
defaults.fatigue.remaining = 200
defaults.fish = {[48496653]=5539,}

settings = config.load(defaults)

-- global variables

bait_id = nil
fish_item_id = nil
fish_bite_id = nil
catch_delay = nil
running = false
log_file = nil
catch_key = nil
last_bite_id = nil
last_item_id = nil

-- debug and logging functions

function message(level, message)
    local prefix = 'E'
    local color = 167
    if level == 1 then
        prefix = 'W'
        color = 200
    elseif level == 2 then
        prefix = 'I'
        color = 207
    elseif level == 3 then
        prefix = 'D'
        color = 160
    end
    if settings.log >= level then
        if log_file == nil then
            log_file = io.open(windower.addon_path .. 'fisher.log', 'a')
        end
        if log_file == nil then
            settings.log = -1
            windower.add_to_chat(167, 'unable to open log file')
        else
            log_file:write('%s | %s | %s\n':format(os.date(), prefix, message))
            log_file:flush()
        end
    end
    if settings.chat >= level then
        windower.add_to_chat(color, message)
    end
end

-- binary helper functions

function string.tohex(str)
    return str:gsub('.', function (c) return '%02X':format(string.byte(c)) end)
end

-- bait helper functions

function check_bait()
    local items = windower.ffxi.get_items()
    message(2, 'checking bait')
    if items.equipment.ammo == 0 then
        message(3, 'item slot: 0')
        return false
    end
    message(3, 'item slot: %d, id: %d':format(items.equipment.ammo, items.inventory[items.equipment.ammo].id))
    return items.inventory[items.equipment.ammo].id == bait_id
end

function equip_bait()
    for slot,item in pairs(windower.ffxi.get_items().inventory) do
        if item.id == bait_id and item.status == 0 then
            message(1, 'equipping bait')
            message(3, 'item slot: %d, id: %d, status: %d':format(slot, item.id, item.status))
            windower.ffxi.set_equip(slot, 3)
            return true
        end
    end
    return false
end

-- inventory helper functions

function check_inventory()
    local items = windower.ffxi.get_items()
    local empty = items.max_inventory
    message(2, 'checking inventory space')
    for _,item in pairs(items.inventory) do
        if item.id ~= 0 then
            empty = empty - 1
        end
    end
    message(3, 'inventory empty: %d, max: %d':format(empty, items.max_inventory))
    return empty > 1
end

function move_fish()
    local items = windower.ffxi.get_items()
    local empty_satchel = items.max_satchel
    message(2, 'checking bag space')
    for _,item in pairs(items.satchel) do
        if item.id ~= 0 then
            empty_satchel = empty_satchel - 1
        end
    end
    message(3, 'satchel empty: %d, max: %d':format(empty_satchel, items.max_satchel))
    local empty_sack = items.max_sack
    for _,item in pairs(items.sack) do
        if item.id ~= 0 then
            empty_sack = empty_sack - 1
        end
    end
    message(3, 'sack empty: %d, max: %d':format(empty_sack, items.max_sack))
    local empty_case = items.max_case
    for _,item in pairs(items.case) do
        if item.id ~= 0 then
            empty_case = empty_case - 1
        end
    end
    message(3, 'case empty: %d, max: %d':format(empty_case, items.max_case))
    if (empty_satchel + empty_sack + empty_case) == 0 then
        return false
    end
    message(1, 'moving fish')
    moved = 0
    for slot,item in pairs(items.inventory) do
        if item.id == fish_item_id and item.status == 0 then
            if empty_satchel > 0 then
                windower.ffxi.put_item(5, slot, item.count)
                empty_satchel = empty_satchel - 1
                moved = moved + 1
            elseif empty_sack > 0 then
                windower.ffxi.put_item(6, slot, item.count)
                empty_sack = empty_sack - 1
                moved = moved + 1
            elseif empty_case > 0 then
                windower.ffxi.put_item(7, slot, item.count)
                empty_sack = empty_sack - 1
                moved = moved + 1
            end
        end
    end
    message(3, 'fish moved: %d':format(moved))
    return moved > 0
end

function move_bait()
    local items = windower.ffxi.get_items()
    local empty = items.max_inventory
    message(2, 'checking inventory space')
    for _,item in pairs(items.inventory) do
        if item.id ~= 0 then
            empty = empty - 1
        end
    end
    message(3, 'inventory empty: %d, max: %d':format(empty, items.max_inventory))
    local count = 20
    if empty < 2 then
        return false
    elseif empty <= count then
        count = math.floor(empty / 2)
    end
    message(1, 'moving bait')
    local moved = 0
    for slot,item in pairs(items.satchel) do
        if item.id == bait_id and count > 0 then
            windower.ffxi.get_item(5, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    for slot,item in pairs(items.sack) do
        if item.id == bait_id and count > 0 then
            windower.ffxi.get_item(6, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    for slot,item in pairs(items.case) do
        if item.id == bait_id and count > 0 then
            windower.ffxi.get_item(7, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    message(3, 'bait moved: %d':format(moved))
    return moved > 0
end

-- fatigue helper functions

function check_fatigued()
    local today = os.date('!%Y-%m-%d', os.time() + 32400)
    message(2, 'checking fatigue')
    if settings.fatigue.date ~= today then
        message(2, 'resetting fatigue')
        settings.fatigue.date = today
        settings.fatigue.remaining = 200
        settings:save('all')
    end
    message(3, 'catches until fatigued: %d':format(settings.fatigue.remaining))
    return settings.fatigue.remaining == 0
end

function update_fatigue(count)
    message(2, 'updating fatigue')
    settings.fatigue.remaining = settings.fatigue.remaining - count
    message(3, 'catches until fatigued: %d':format(settings.fatigue.remaining))
    settings:save('all')
end

-- fish id helper functions

function get_bite_id()
    for bite_id,item_id in pairs(settings.fish) do
        if item_id == fish_item_id then
            return bite_id
        end
    end
    return nil
end

-- action functions

function catch()
    if running then
        local player = windower.ffxi.get_player()
        message(2, 'catching fish')
        windower.packets.inject_outgoing(0x110, 'IIIHH':pack(0xB10, player.id, 0, player.index, 3) .. catch_key)
    end
end

function release()
    if running then
        local player = windower.ffxi.get_player()
        message(2, 'releasing fish')
        windower.packets.inject_outgoing(0x110, 'IIIHHI':pack(0xB10, player.id, 200, player.index, 3, 0))
    end
end

function cast()
    if running then
        if check_fatigued() then
            message(0, 'fatigued')
            fisher_command('stop')
        elseif check_inventory() then
            if check_bait() then
                message(2, 'casting')
                windower.send_command('input /fish')
            elseif settings.equip and equip_bait() then
                message(2, 'casting in %d seconds':format(settings.delay.equip))
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.equip))
            elseif settings.move and move_bait() then
                message(2, 'casting in %d seconds':format(settings.delay.move))
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
            else
                message(0, 'out of bait')
                fisher_command('stop')
            end
        elseif settings.move and move_fish() then
            message(2, 'casting in %d seconds':format(settings.delay.move))
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
        else
            message(0, 'inventory full')
            fisher_command('stop')
        end
    end
end

-- event callback functions

function check_status_change(new_status_id, old_status_id)
    if running then
        message(0, 'status changed')
        message(3, 'status new: %d, old: %d':format(new_status_id, old_status_id))
        fisher_command('stop')
    end
end

function check_zone_change(new_id, old_id)
    if running then
        message(0, 'zone changed')
        message(3, 'zone new: %d, old: %d':format(new_id, old_id))
        fisher_command('stop')
    end
end

function check_chat_message(message, sender, mode, gm)
    if running and gm then
        message(0, 'incoming gm chat')
        message(3, 'chat from: %s, mode: %d':format(sender, mode))
        fisher_command('stop')
    end
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x115 then
            message(3, 'incoming fish info: ' .. original:tohex())
            last_bite_id = original:unpack('I', 11)
            if last_item_id ~= nil then
                if last_item_id == fish_item_id then
                    fish_bite_id = last_bite_id
                elseif fish_bite_id == last_bite_id then
                    fish_bite_id = nil
                end
                settings.fish[last_bite_id] = last_item_id
                last_item_id = nil
            end
            if fish_bite_id == last_bite_id or (fish_bite_id == nil and settings.fish[last_bite_id] == nil) then
                catch_key = original:sub(21)
                message(2, 'catching fish in %d seconds':format(catch_delay))
                windower.send_command('wait %d; lua i fisher catch':format(catch_delay))
            else
                message(2, 'releasing fish in %d seconds':format(settings.delay.release))
                windower.send_command('wait %d; lua i fisher release':format(settings.delay.release))
            end
        elseif id == 0x2A and windower.ffxi.get_player().id == original:unpack('I', 5) then
            message(3, 'incoming fish intuition: ' .. original:tohex())
            last_item_id = original:unpack('I', 9)
        elseif id == 0x27 and windower.ffxi.get_player().id == original:unpack('I', 5) then
            message(3, 'incoming fish caught: ' .. original:tohex())
            last_item_id = original:unpack('I', 17)
            if last_item_id == fish_item_id then
                fish_bite_id = last_bite_id
            elseif fish_bite_id == last_bite_id then
                fish_bite_id = nil
            end
            settings.fish[last_bite_id] = last_item_id
            last_item_id = nil
            windower.send_command('lua i fisher update_fatigue 1')
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x110 then
            message(3, 'outgoing fishing action: ' .. original:tohex())
            if original:byte(15) == 4 then
                message(2, 'casting in %d seconds':format(settings.delay.cast))
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.cast))
            end
        elseif id == 0x1A then
            if original:unpack('H', 11) == 14 then
                message(3, 'outgoing fish command: ' .. original:tohex())
            else
                message(0, 'outgoing command')
                fisher_command('stop')
            end
        end
    end
end

function fisher_command(...)
    if #arg == 4 and arg[1]:lower() == 'start' then
        bait_id = tonumber(arg[2])
        fish_item_id = tonumber(arg[3])
        catch_delay = tonumber(arg[4])
        fish_bite_id = get_bite_id()
        running = true
        message(1, 'started fishing')
        cast()
    elseif #arg == 1 and arg[1]:lower() == 'stop' then
        running = false
        message(1, 'stopped fishing')
        if log_file ~= nil then
            log_file:close()
            log_file = nil
        end
    elseif #arg == 2 and arg[1]:lower() == 'chat' then
        settings.chat = tonumber(arg[2]) or 1
        windower.add_to_chat(200, 'chat message level: %s':format(settings.chat >= 0 and settings.chat or 'off'))
        settings:save('all')
    elseif #arg == 2 and arg[1]:lower() == 'log' then
        settings.log = tonumber(arg[2]) or -1
        windower.add_to_chat(200, 'log message level: %s':format(settings.log >= 0 and settings.log or 'off'))
        settings:save('all')
        if settings.log < 0 and log_file ~= nil then
            log_file:close()
            log_file = nil
        end
    elseif #arg == 2 and arg[1]:lower() == 'equip' then
        settings.equip = (arg[2]:lower() == 'on')
        windower.add_to_chat(200, 'equip bait: %s':format(settings.equip and 'on' or 'off'))
        settings:save('all')
    elseif #arg == 2 and arg[1]:lower() == 'move' then
        settings.move = (arg[2]:lower() == 'on')
        windower.add_to_chat(200, 'move bait and fish: %s':format(settings.move and 'on' or 'off'))
        settings:save('all')
    else
        windower.add_to_chat(167, 'usage: fisher start <bait id> <fish id> <catch delay>')
        windower.add_to_chat(167, '        fisher stop')
        windower.add_to_chat(167, '        fisher chat <level>')
        windower.add_to_chat(167, '        fisher log <level>')
        windower.add_to_chat(167, '        fisher equip <on/off>')
        windower.add_to_chat(167, '        fisher move <on/off>')
    end
end

-- register event callbacks

windower.register_event('status change', check_status_change)
windower.register_event('zone change', check_zone_change)
windower.register_event('chat message', check_chat_message)
windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('addon command', fisher_command)
