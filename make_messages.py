import array
import struct

from settings import search, zones


def find_dat(dat_id):
    ffxi_path = 'C:\\Program Files (x86)\\PlayOnline\\SquareEnix\\FINAL FANTASY XI\\'
    for i in range(1, 10):
        vtable = None
        if i == 1:
            vtable = open('{}VTABLE.DAT'.format(ffxi_path), 'rb')
        else:
            vtable = open('{}ROM{}\\VTABLE{}.DAT'.format(ffxi_path, i, i), 'rb')
        vtable.seek(dat_id)
        temp = vtable.read(1)[0]
        vtable.close()
        if temp != i:
            continue
        ftable = None
        if i == 1:
            ftable = open('{}FTABLE.DAT'.format(ffxi_path), 'rb')
        else:
            ftable = open('{}ROM{}\\FTABLE{}.DAT'.format(ffxi_path, i, i), 'rb')
        ftable.seek(dat_id * 2)
        path = struct.unpack('H', ftable.read(2))[0]
        ftable.close()
        if i == 1:
            return '{}ROM\\{}\\{}.DAT'.format(ffxi_path, path >> 7, path & 0x7f)
        else:
            return '{}ROM{}\\{}\\{}.DAT'.format(ffxi_path, i, path >> 7, path & 0x7f)
    return None

def decipher_dialog(dat_file):
    dat = open(dat_file, 'rb')
    dat_size, first_entry = struct.unpack('II', dat.read(8))
    dat_size -= 0x10000000
    first_entry ^= 0x80808080
    dat.seek(4)
    data = bytearray(dat.read())
    dat.close()
    for i in range(len(data)):
        data[i] ^= 0x80
    offsets = array.array('I', data[:first_entry])
    offsets.append(dat_size)
    for i in range(len(offsets)):
        offsets[i] -= first_entry
    return offsets, bytes(data[first_entry:])

def search_dialog(zones, search):
    messages = {}
    for zone_id, dat_id in zones.items():
        offsets, data = decipher_dialog(find_dat(dat_id))
        for i in range(len(offsets) - 1):
            message = data[offsets[i]:offsets[i+1]]
            for name, string in search.items():
                if message == string:
                    if messages.get(zone_id) is None:
                        messages[zone_id] = {name: i}
                    else:
                        messages[zone_id][name] = i
    return messages

def write_lua(messages):
    o = open('messages.lua', 'w')
    print('messages = {}', file=o)
    for zone_id, message_ids in messages.items():
        line = []
        for name, message_id in message_ids.items():
            line.append('{}={}'.format(name, message_id))
        line = ', '.join(line)
        print("messages[{}] = {{{}}}".format(zone_id, line), file=o)
    o.close()

write_lua(search_dialog(zones, search))
