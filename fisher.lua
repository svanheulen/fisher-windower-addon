--[[
Copyright 2014 Seth VanHeulen

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version. 

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

-- addon information

_addon.name = 'fisher'
_addon.version = '3.0.0'
_addon.command = 'fisher'
_addon.author = 'Seth VanHeulen (Acacia@Odin)'

-- modules

config = require('config')
res = require('resources')
require('lists')
require('pack')
require('sets')
require('strings')

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
defaults.fish = {}

settings = config.load('data/%s.xml':format(windower.ffxi.get_player().name), defaults)

-- global variables

catch = {small=T{}, large=T{}, item=T{}, monster=false}
bait = S{}
stats = {casts=0, bites=0, catches=0}

running = false
log_file = nil

-- global constants

messages = {}
messages.small = S{7028}
messages.large = S{7070}
messages.item = S{7071}
messages.monster = S{7072}
messages.senses = S{7073}
messages.time = S{7060}
messages.catch = S{7025, 7030, 7034, 7048, 7059}

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
            log_file = io.open('%sdata/%s.log':format(windower.addon_path, windower.ffxi.get_player().name), 'a')
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

-- bait helper functions

function check_bait()
    local items = windower.ffxi.get_items()
    message(2, 'checking bait')
    if items.equipment.ammo == 0 then
        return false
    elseif items.equipment.ammo_bag == 0 then
        return bait:contains(items.inventory[items.equipment.ammo].id)
    else
        return bait:contains(items.wardrobe[items.equipment.ammo].id)
    end
end

function equip_bait()
    for slot,item in pairs(windower.ffxi.get_items().inventory) do
        if bait:contains(item.id) and item.status == 0 then
            windower.ffxi.set_equip(slot, 3, 0)
            return true
        end
    end
    for slot,item in pairs(windower.ffxi.get_items().wardrobe) do
        if bait:contains(item.id) and item.status == 0 then
            windower.ffxi.set_equip(slot, 3, 8)
            return true
        end
    end
    return false
end

-- inventory helper functions

function check_inventory()
    local items = windower.ffxi.get_items()
    return (items.max_inventory - items.count_inventory) > 1
end

function move_fish()
    local items = windower.ffxi.get_items()
    local empty_satchel = items.max_satchel - items.count_satchel
    local empty_sack = items.max_sack - items.count_sack
    local empty_case = items.max_case - items.count_case
    if (empty_satchel + empty_sack + empty_case) == 0 then
        return false
    end
    local moved = 0
    for slot,item in pairs(items.inventory) do
        if (catch.small[item.id] or catch.large[item.id] or catch.item[item.id]) and item.status == 0 then
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
    return moved > 0
end

function move_bait()
    local items = windower.ffxi.get_items()
    local empty = items.max_inventory - items.count_inventory
    local count = 20
    if empty < 2 then
        return false
    elseif empty <= count then
        count = math.floor(empty / 2)
    end
    local moved = 0
    for slot,item in pairs(items.satchel) do
        if bait:contains(item.id) and count > 0 then
            windower.ffxi.get_item(5, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    for slot,item in pairs(items.sack) do
        if bait:contains(item.id) and count > 0 then
            windower.ffxi.get_item(6, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    for slot,item in pairs(items.case) do
        if bait:contains(item.id) and count > 0 then
            windower.ffxi.get_item(7, slot, item.count)
            count = count - 1
            moved = moved + 1
        end
    end
    return moved > 0
end

-- fatigue helper functions

function check_fatigued()
    update_day()
    return settings.fatigue.remaining == 0
end

function update_day()
    local today = os.date('!%Y-%m-%d', os.time() + 32400)
    if settings.fatigue.date ~= today then
        settings.fatigue.date = today
        settings.fatigue.remaining = 200
        settings:save('all')
    end
end

function update_fatigue()
    settings.fatigue.remaining = settings.fatigue.remaining - current.count
    update_fish()
end

-- fish id helper functions

function get_bite_id(id)
    for bite_id,item_id in pairs(settings.fish) do
        if item_id == id then
            return tonumber(bite_id)
        end
    end
    return nil
end

function update_fish()
    if catch[current.type][current.item_id] ~= nil then
        catch[current.type][current.item_id].bite_id = current.bite_id
    elseif catch[current.type]:with('bite_id', current.bite_id) ~= nil then
        catch[current.type]:with('bite_id', current.bite_id).bite_id = nil
    end
    settings.fish[tostring(current.bite_id)] = current.item_id
    settings:save('all')
end

-- action functions

function catch(casts)
    if running and stats.casts == tonumber(casts) then
        local player = windower.ffxi.get_player()
        windower.packets.inject_outgoing(0x110, 'IIIHH':pack(0xB10, player.id, 0, player.index, 3) .. current.key)
    end
end

function release(casts)
    if running and stats.casts == tonumber(casts) then
        local player = windower.ffxi.get_player()
        windower.packets.inject_outgoing(0x110, 'IIIHHI':pack(0xB10, player.id, 200, player.index, 3, 0))
    end
end

function cast()
    if running then
        if check_fatigued() then
            fisher_command('stop')
        elseif check_inventory() then
            if check_bait() then
                windower.send_command('input /fish')
            elseif settings.equip and equip_bait() then
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.equip))
            elseif settings.move and move_bait() then
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
            else
                fisher_command('stop')
            end
        elseif settings.move and move_fish() then
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
        else
            fisher_command('stop')
        end
    end
end

-- event callback functions

function check_action(action)
    if running then
        local player_id = windower.ffxi.get_player().id
        for _,target in pairs(action.targets) do
            if target.id == player_id then
                fisher_command('stop')
                return
            end
        end
    end
end

function check_status_change(new_status_id, old_status_id)
    if running and new_status_id ~= 0 and new_status_id ~= 50 then
        fisher_command('stop')
    end
end

function check_chat_message(message, sender, mode, gm)
    if running and gm then
        fisher_command('stop')
    end
end

function check_incoming_text(original, modified, original_mode, modified_mode, blocked)
    if running and original:find('You cannot fish here.') ~= nil then
        if error_retry then
            error_retry = false
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.cast))
        else
            fisher_command('stop')
        end
    end
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x36 then
            local message_id = original:unpack('H', 11) % 0x8000
            if messages.small:contains(message_id) then
                current.type = 'small'
                stats.bites = stats.bites + 1
            elseif messages.large:contains(message_id) then
                current.type = 'large'
                stats.bites = stats.bites + 1
            elseif messages.item:contains(message_id) then
                current.type = 'item'
                stats.bites = stats.bites + 1
            elseif messages.monster:contains(message_id) then
                current.type = 'monster'
                stats.bites = stats.bites + 1
            elseif messages.time:contains(message_id) then
                catch(stats.casts)
            end
        elseif id == 0x2A then
            local message_id = original:unpack('H', 27) % 0x8000
            if messages.senses:contains(message_id) then
                current.item_id = original:unpack('I', 9)
                update_fish()
            end
        elseif id == 0x115 then
            current.bite_id = original:unpack('I', 11)
            if (current.type == 'monster' and catch.monster) or (current.type ~= 'monster' and catch[current.type]:with('bite_id', current.bite_id)) then
                current.key = original:sub(21)
                windower.send_command('wait %d; lua i fisher catch %d':format(catch[current.type]:with('bite_id', current.bite_id).delay, stats.casts))
            elseif current.type ~= 'monster' and catch[current.type]:with('bite_id', nil) and settings.fish[tostring(current.bite_id)] == nil then
                current.key = original:sub(21)
            else
                windower.send_command('wait %d; lua i fisher release %d':format(settings.delay.release, stats.casts))
            end
        elseif id == 0x27 and windower.ffxi.get_player().id == original:unpack('I', 5) then
            local message_id = original:unpack('H', 11) % 0x8000
            if messages.catch:contains(message_id) then
                current.item_id = original:unpack('I', 17)
                current.count = 1
                stats.catches = stats.catches + 1
                update_fatigue()
            end
        end
    end
end

function check_outgoing_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x1A then
            if original:unpack('H', 11) == 14 then
                current = {}
                stats.casts = stats.casts + 1
                error_retry = true
            else
                fisher_command('stop')
            end
        elseif id == 0x110 and original:byte(15) == 4 then
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.cast))
        end
    end
end

function check_login(name)
    settings = config.load('data/%s.xml':format(name), defaults)
end

function check_logout(name)
    settings:save('all')
end

-- command functions

function fish_command(arg)
    if #arg > 2 and arg[2]:lower() == 'add' then
        local bite_type = arg[3]:lower()
        if #arg == 5 and (bite_type == 'small' or bite_type == 'large' or bite_type == 'item') then
            local item_id = tonumber(arg[4])
            if item_id == nil then
                _,item_id = res.items:with('name', arg[4])
                if item_id == nil then
                    -- error
                    return
                end
            end
            local delay = tonumber(arg[5])
            if delay == nil then
                -- error
                return
            end
            catch[bite_type][item_id] = {delay=delay, bite_id=get_bite_id(item_id)}
        elseif #arg == 3 and bite_type == 'monster' then
            catch.monster = true
        else
            -- error
        end
    elseif #arg > 2 and arg[2]:lower() == 'remove' then
        local bite_type = arg[3]:lower()
        if #arg == 4 and (bite_type == 'small' or bite_type == 'large' or bite_type == 'item') then
            if arg[4]:lower() == '*' then
                catch[bite_type]:clear()
                return
            end
            local item_id = tonumber(arg[4])
            if item_id == nil then
                _,item_id = res.items:with('name', arg[4])
                if item_id == nil then
                    -- error
                    return
                end
            end
            catch[bite_type]:delete(item_id)
        elseif #arg == 3 and bite_type == '*' then
            catch.small:clear()
            catch.large:clear()
            catch.item:clear()
            catch.monster = false
        else
            -- error
        end
    end
end

function bait_command(arg)
    if #arg == 3 and arg[2]:lower() == 'add' then
        local item_id = tonumber(arg[3])
        if item_id == nil then
            _,item_id = res.items:with('name', arg[3])
            if item_id == nil then
                -- error
                return
            end
        end
        bait:add(item_id)
    elseif #arg == 3 and arg[2]:lower() == 'remove' then
        if arg[3]:lower() == '*' then
            bait:clear()
            return
        end
        local item_id = tonumber(arg[3])
        if item_id == nil then
            _,item_id = res.items:with('name', arg[3])
            if item_id == nil then
                -- error
                return
            end
        end
        bait:remove(item_id)
    end
end

function fisher_command(...)
    if #arg > 2 and arg[1]:lower() == 'fish' then
        fish_command(arg)
    elseif #arg == 3 and arg[1]:lower() == 'bait' then
        bait_command(arg)
    elseif #arg == 1 and arg[1]:lower() == 'start' then
        if running then
            windower.add_to_chat(167, 'already fishing')
            return
        end
        error_retry = true
        running = true
        cast()
    elseif #arg == 1 and arg[1]:lower() == 'stop' then
        if not running then
            windower.add_to_chat(167, 'not fishing')
            return
        end
        running = false
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
    elseif #arg == 1 and arg[1]:lower() == 'reset' then
        windower.add_to_chat(200, 'resetting fish database')
        settings.fish = {}
        settings:save('all')
        fisher_command('fish', 'remove', '*')
    elseif #arg == 1 and arg[1]:lower() == 'stats' then
        local losses = stats.bites - stats.catches
        local bite_rate = 0
        local loss_rate = 0
        local catch_rate = 0
        if stats.casts ~= 0 then
            bite_rate = (stats.bites / stats.casts) * 100
            loss_rate = (losses / stats.casts) * 100
            catch_rate = (stats.catches / stats.casts) * 100
        end
        local lost_bite_rate = 0
        local catch_bite_rate = 0
        if stats.bites ~= 0 then
            loss_bite_rate = (losses / stats.bites) * 100
            catch_bite_rate = (stats.catches / stats.bites) * 100
        end
        if running == false then
            update_day()
        end
        windower.add_to_chat(200, 'casts: %d, remaining fatigue: %d':format(stats.casts, settings.fatigue.remaining))
        windower.add_to_chat(200, 'bites: %d, bite rate: %d%%':format(stats.bites, bite_rate))
        windower.add_to_chat(200, 'catches: %d, catch rate: %d%%, catch/bite rate: %d%%':format(stats.catches, catch_rate, catch_bite_rate))
        windower.add_to_chat(200, 'losses: %d, loss rate: %d%%, loss/bite rate: %d%%':format(losses, loss_rate, loss_bite_rate))
    elseif #arg == 2 and arg[1]:lower() == 'fatigue' then
        local count = tonumber(arg[2])
        if count == nil then
            windower.add_to_chat(167, 'invalid count')
        elseif count < 0 then
            if running == false then
                update_day()
            end
            settings.fatigue.remaining = settings.fatigue.remaining + count
            windower.add_to_chat(200, 'remaining fatigue: %d':format(settings.fatigue.remaining))
            settings:save('all')
        else
            settings.fatigue.remaining = count
            windower.add_to_chat(200, 'remaining fatigue: %d':format(settings.fatigue.remaining))
            settings:save('all')
        end
    else
        windower.add_to_chat(167, 'usage: fisher start <bait> <fish> <catch delay>')
        windower.add_to_chat(167, '        fisher restart')
        windower.add_to_chat(167, '        fisher stop')
        windower.add_to_chat(167, '        fisher chat <level>')
        windower.add_to_chat(167, '        fisher log <level>')
        windower.add_to_chat(167, '        fisher equip <on/off>')
        windower.add_to_chat(167, '        fisher move <on/off>')
        windower.add_to_chat(167, '        fisher reset')
        windower.add_to_chat(167, '        fisher stats')
        windower.add_to_chat(167, '        fisher fatigue <count>')
    end
end

-- register event callbacks

windower.register_event('action', check_action)
windower.register_event('status change', check_status_change)
windower.register_event('chat message', check_chat_message)
windower.register_event('incoming text', check_incoming_text)
windower.register_event('incoming chunk', check_incoming_chunk)
windower.register_event('outgoing chunk', check_outgoing_chunk)
windower.register_event('login', check_login)
windower.register_event('logout', check_logout)
windower.register_event('addon command', fisher_command)
