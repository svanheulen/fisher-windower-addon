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

require('luau')
require('pack')

-- default settings

defaults = {}
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

-- global variables

fish = T{}
bait = S{}
stats = {casts=0, bites=0, catches=0}

running = false

-- global constants

messages = {}
messages.fish = S{7028, 7070, 7071, 7675, 7717, 7718, 6862, 6904, 6905}
messages.monster = S{7072, 7719, 6906}
messages.senses = S{7073, 7720, 6907}
messages.time = S{7060, 7707, 6894}
messages.catch = S{7025, 7030, 7034, 7048, 7059, 7672, 7677, 7681, 7695, 7706, 6859, 6864, 6868, 6882, 6893}

-- bait helper functions

function check_bait()
    local items = windower.ffxi.get_items()
    notice('checking equipped bait')
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
            warning('equipping bait')
            windower.ffxi.set_equip(slot, 3, 0)
            return true
        end
    end
    for slot,item in pairs(windower.ffxi.get_items().wardrobe) do
        if bait:contains(item.id) and item.status == 0 then
            warning('equipping bait')
            windower.ffxi.set_equip(slot, 3, 8)
            return true
        end
    end
    return false
end

-- inventory helper functions

function check_inventory()
    local items = windower.ffxi.get_items()
    notice('checking inventory space')
    return (items.max_inventory - items.count_inventory) > 1
end

function move_fish()
    local items = windower.ffxi.get_items()
    notice('checking bag space')
    local empty_satchel = items.max_satchel - items.count_satchel
    local empty_sack = items.max_sack - items.count_sack
    local empty_case = items.max_case - items.count_case
    if (empty_satchel + empty_sack + empty_case) == 0 then
        return false
    end
    warning('moving fish to bags')
    local moved = 0
    for slot,item in pairs(items.inventory) do
        if fish[item.id] ~= nil and item.status == 0 then
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
    notice('checking inventory space')
    local empty = items.max_inventory - items.count_inventory
    local count = 20
    if empty < 2 then
        return false
    elseif empty <= count then
        count = math.floor(empty / 2)
    end
    warning('moving bait to inventory')
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
    notice('checking fishing fatigue')
    return settings.fatigue.remaining == 0
end

function update_day()
    local today = os.date('!%Y-%m-%d', os.time() + 32400)
    if settings.fatigue.date ~= today then
        notice('resetting fishing fatigue')
        settings.fatigue.date = today
        settings.fatigue.remaining = 200
        settings:save('all')
    end
end

function update_fatigue()
    notice('updating fishing fatigue')
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
    notice('updating fish database')
    if fish[current.item_id] ~= nil then
        fish[current.item_id].bite_id = current.bite_id
    elseif fish:with('bite_id', current.bite_id) then
        fish:with('bite_id', current.bite_id).bite_id = nil
    end
    settings.fish[tostring(current.bite_id)] = current.item_id
    settings:save('all')
end

-- action functions

function catch(casts)
    if running and stats.casts == tonumber(casts) then
        local player = windower.ffxi.get_player()
        warning('sending catch command')
        windower.packets.inject_outgoing(0x110, 'IIIHH':pack(0xB10, player.id, 0, player.index, 3) .. current.key)
    end
end

function release(casts)
    if running and stats.casts == tonumber(casts) then
        local player = windower.ffxi.get_player()
        warning('sending release command')
        windower.packets.inject_outgoing(0x110, 'IIIHHI':pack(0xB10, player.id, 200, player.index, 3, 0))
    end
end

function cast()
    if running then
        if check_fatigued() then
            error('reached fishing fatigue')
            fisher_command('stop')
        elseif check_inventory() then
            if check_bait() then
                warning('casting fishing rod')
                windower.send_command('input /fish')
            elseif settings.equip and equip_bait() then
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.equip))
            elseif settings.move and move_bait() then
                windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
            else
                error('out of bait')
                fisher_command('stop')
            end
        elseif settings.move and move_fish() then
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.move))
        else
            error('inventory is full')
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
                error('action performed on you')
                fisher_command('stop')
                return
            end
        end
    end
end

function check_status_change(new_status_id, old_status_id)
    if running and new_status_id ~= 0 and new_status_id ~= 50 then
        error('status was changed')
        fisher_command('stop')
    end
end

function check_chat_message(message, sender, mode, gm)
    if running and gm then
        error('received message from gm')
        fisher_command('stop')
    end
end

function check_incoming_text(original, modified, original_mode, modified_mode, blocked)
    if running and original:find('You cannot fish here.') ~= nil then
        if error_retry then
            error_retry = false
            windower.send_command('wait %d; lua i fisher cast':format(settings.delay.cast))
        else
            error('unable to fish')
            fisher_command('stop')
        end
    end
end

function check_incoming_chunk(id, original, modified, injected, blocked)
    if running then
        if id == 0x36 then
            local message_id = original:unpack('H', 11) % 0x8000
            if messages.fish:contains(message_id) then
                current.monster = false
            elseif messages.monster:contains(message_id) then
                current.monster = true
            elseif messages.time:contains(message_id) then
                catch(stats.casts)
            end
        elseif id == 0x2A then
            local message_id = original:unpack('H', 27) % 0x8000
            if messages.senses:contains(message_id) then
                current.item_id = original:unpack('I', 9)
            end
        elseif id == 0x115 then
            current.bite_id = original:unpack('I', 11)
            if current.item_id ~= nil then
                update_fish()
            end
            if current.monster == false and fish:with('bite_id', current.bite_id) then
                current.key = original:sub(21)
                stats.bites = stats.bites + 1
                windower.send_command('wait %d; lua i fisher catch %d':format(fish:with('bite_id', current.bite_id).delay, stats.casts))
            elseif current.monster == false and fish:with('bite_id', nil) and settings.fish[tostring(current.bite_id)] == nil then
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
                error('performed an action')
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

function check_load()
    if windower.ffxi.get_info().logged_in then
        settings = config.load('data/%s.xml':format(windower.ffxi.get_player().name), defaults)
    end
end

function check_unload()
    settings:save('all')
end

-- command functions

function fish_command(arg)
    if #arg == 4 and arg[2]:lower() == 'add' then
        local item_id = tonumber(arg[3])
        if item_id == nil then
            _,item_id = res.items:with('name', arg[3])
            if item_id == nil then
                error('invalid fish name or item id')
                return
            end
        end
        local delay = tonumber(arg[4])
        if delay == nil then
            error('invalid cast delay time')
            return
        end
        fish[item_id] = {delay=delay, bite_id=get_bite_id(item_id)}
        notice('added fish, name: %s, item id: %d, delay: %d, bite id: %s':format(res.items[item_id].name, item_id, delay, fish.bite_id or 'unknown'))
    elseif #arg == 3 and arg[2]:lower() == 'remove' then
        if arg[3]:lower() == '*' then
            notice('removed all fish')
            fish:clear()
            return
        end
        local item_id = tonumber(arg[3])
        if item_id == nil then
            _,item_id = res.items:with('name', arg[3])
            if item_id == nil then
                error('invalid fish name or item id')
                return
            end
        end
        fish[item_id] = nil
        notice('removed fish, name: %s, item id: %d':format(res.items[item_id].name, item_id))
    elseif #arg == 2 and arg[2]:lower() == 'list' then
        if fish:length() == 0 then
            notice('fish list is empty')
            return
        end
        for item_id,value in pairs(fish) do
            notice('name: %s, item id: %d, delay: %d, bite id: %s':format(res.items[item_id].name, item_id, value.delay, value.bite_id or 'unknown'))
        end
    else
        error('fisher fish add <name or item id> <catch delay>')
        error('fisher fish remove <name or item id>')
        error('fisher fish remove *')
        error('fisher fish list')
    end
end

function bait_command(arg)
    if #arg == 3 and arg[2]:lower() == 'add' then
        local item_id = tonumber(arg[3])
        if item_id == nil then
            _,item_id = res.items:with('name', arg[3])
            if item_id == nil then
                error('invalid bait name or item id')
                return
            end
        end
        bait:add(item_id)
        notice('added bait, name: %s, item id: %d':format(res.items[item_id].name, item_id))
    elseif #arg == 3 and arg[2]:lower() == 'remove' then
        if arg[3]:lower() == '*' then
            notice('removed all bait')
            bait:clear()
            return
        end
        local item_id = tonumber(arg[3])
        if item_id == nil then
            _,item_id = res.items:with('name', arg[3])
            if item_id == nil then
                error('invalid bait name or item id')
                return
            end
        end
        bait:remove(item_id)
        notice('removed bait, name: %s, item id: %d':format(res.items[item_id].name, item_id))
    elseif #arg == 2 and arg[2]:lower() == 'list' then
        if bait:length() == 0 then
            notice('bait list is empty')
            return
        end
        for item_id,_ in pairs(bait) do
            notice('name: %s, item id: %d':format(res.items[item_id].name, item_id))
        end
    else
        error('fisher bait add <name or item id>')
        error('fisher bait remove <name or item id>')
        error('fisher bait remove *')
        error('fisher bait list')
    end
end

function fisher_command(...)
    if windower.ffxi.get_info().logged_in == false then
        error('not logged in')
        return
    end
    if #arg >= 1 and arg[1]:lower() == 'fish' then
        fish_command(arg)
    elseif #arg >= 1 and arg[1]:lower() == 'bait' then
        bait_command(arg)
    elseif #arg == 1 and arg[1]:lower() == 'start' then
        if running then
            error('already fishing')
            return
        end
        if fish:empty() or bait:empty() then
            error('no fish or bait configured')
            return
        end
        error_retry = true
        running = true
        warning('started fishing')
        cast()
    elseif #arg == 1 and arg[1]:lower() == 'stop' then
        if not running then
            error('not fishing')
            return
        end
        running = false
        warning('stopped fishing')
    elseif #arg == 2 and arg[1]:lower() == 'equip' then
        settings.equip = (arg[2]:lower() == 'on')
        notice('equip bait: %s':format(settings.equip and 'on' or 'off'))
        settings:save('all')
    elseif #arg == 2 and arg[1]:lower() == 'move' then
        settings.move = (arg[2]:lower() == 'on')
        notice('move bait and fish: %s':format(settings.move and 'on' or 'off'))
        settings:save('all')
    elseif #arg == 1 and arg[1]:lower() == 'reset' then
        notice('resetting fish database')
        settings.fish = {}
        settings:save('all')
        fish:clear()
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
        local loss_bite_rate = 0
        local catch_bite_rate = 0
        if stats.bites ~= 0 then
            loss_bite_rate = (losses / stats.bites) * 100
            catch_bite_rate = (stats.catches / stats.bites) * 100
        end
        if running == false then
            update_day()
        end
        notice('casts: %d, remaining fatigue: %d':format(stats.casts, settings.fatigue.remaining))
        notice('bites: %d, bite rate: %d%%':format(stats.bites, bite_rate))
        notice('catches: %d, catch rate: %d%%, catch/bite rate: %d%%':format(stats.catches, catch_rate, catch_bite_rate))
        notice('losses: %d, loss rate: %d%%, loss/bite rate: %d%%':format(losses, loss_rate, loss_bite_rate))
    elseif #arg == 2 and arg[1]:lower() == 'fatigue' then
        local count = tonumber(arg[2])
        if count == nil then
            error('invalid count')
        elseif count < 0 then
            if running == false then
                update_day()
            end
            settings.fatigue.remaining = settings.fatigue.remaining + count
            notice('remaining fatigue: %d':format(settings.fatigue.remaining))
            settings:save('all')
        else
            settings.fatigue.remaining = count
            notice('remaining fatigue: %d':format(settings.fatigue.remaining))
            settings:save('all')
        end
    else
        error('fisher fish ...')
        error('fisher bait ...')
        error('fisher start')
        error('fisher stop')
        error('fisher equip <on/off>')
        error('fisher move <on/off>')
        error('fisher fatigue <count>')
        error('fisher stats')
        error('fisher reset')
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
windower.register_event('load', check_load)
windower.register_event('unload', check_unload)
windower.register_event('addon command', fisher_command)
