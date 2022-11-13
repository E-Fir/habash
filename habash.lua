require 'lua-nucleo'
local tpretty = import 'lua-nucleo/tpretty.lua' { 'tpretty_ordered' }
local tstr = (require 'lua-nucleo.table').tstr

local reset_color =   '\x1b[0m'
local gray =          '\x1b[30;90m'
local light_red =     '\x1b[30;91m'
local light_blue =    '\x1b[30;94m'
local light_yellow =  '\x1b[30;93m'

local json = require 'json'

local input
local data

local is_full = false
--if true then
--  declare('socket') declare('loadstring')
--  declare('getfenv') declare('setfenv')
--  local m = require('mobdebug')
--  m.start('192.168.3.93')
--end
local args = { }
for i = 1, #arg do
  if arg[i] == '--full' then
    is_full = true
  else
    args[#args + 1] = arg[i]
  end
end

local mode = arg[1]
local TAGS_FILENAME = 'tags.lua'
local FINAL_ITEMS_FILENAME = 'last_items.lua'
local IGNORE_FILENAME = 'ignore.lua'

local today = os.date('%Y-%m-%d')

if mode == 'postpone' then
  print('NIY')
  os.exit(1)
end

if mode == 'tags' then
  input = io.read('*a')
  data = json.decode(input)

  local tags = { }
  for _, item in pairs(data.data) do
    tags[item.id] = item.name
  end
  local f = io.open(TAGS_FILENAME, 'w')
  f:write('return ' .. tstr(tags))
  f:close()

  os.execute('cat ' .. TAGS_FILENAME)
  return
end

local load_items = function()
  local items = loadfile(FINAL_ITEMS_FILENAME)()
  return items
end

if mode == 'get_task_id_by_pos' then
  local items = load_items()
  local res = { }
  for i = 2, #arg do
    local pos = tonumber(arg[i])
    res[#res + 1] = items[pos].id
  end
  print(table.concat(res, ' '))
  return
end

local ignores_func = loadfile(IGNORE_FILENAME)
local ignores = ignores_func and ignores_func() or { }
local today_ignores = ignores[today] or { }

if mode == 'ignore' then
  local pos = tonumber(arg[2])
  local items = load_items()

  today_ignores[items[pos].id] = true
  ignores[today] = today_ignores

  local f = io.open(IGNORE_FILENAME, 'w')
  f:write('return ' .. tstr(ignores))
  f:close()

  print(tpretty(ignores))
  return
end

if mode ~= 'dailys' then
  print(tpretty(data))
  return
end

input = io.read('*a')
data = json.decode(input)

local tags = loadfile(TAGS_FILENAME)()

local items = data.data
local MONTHS =
{
  Jan = '01';
  Feb = '02';
  Mar = '03';
  Apr = '04';
  May = '05';
  Jul = '07';
  Sep = '09';
  Oct = '10';
  Nov = '11';
  Dec = '12';
}

local to_date = function(date, use_day_shift)
  if type(date) == 'number' then
    return os.date('%Y-%m-%d', math.floor(date / 1000))
  end

  local month
  local res
  local weekday, month_name, day, year, hour, minute, second, gmt_offset =
    date:match('^(%w+) (%w+) (%d+) (%d+) (%d+):(%d+):(%d+) GMT%+(%d+)')
  if weekday then
    if not MONTHS[month_name] then
      error('Unknown month: ' .. month_name)
    end
    day = ('0' .. (tonumber(day) - 1)):sub(-2)
    res = year .. '-' .. MONTHS[month_name] .. '-' .. day
  else
    year, month, day, hour = date:match('^(%d+)-(%d+)-(%d+)T(%d+)')
    if not year then
      error('Can\'t parse `date`: ' .. date)
    end
    hour = tonumber(hour)
    if use_day_shift and hour >= 21 then
      day = day + 1
    end
    day = ('0' .. tonumber(day)):sub(-2)
    res = year .. '-' .. month .. '-' .. day
  end

  return res
end

for i = 1, #items do
  local item = items[i]
  if
    item.text:find('dust')
    --or item.text:find('Order food')
  then
    print(tpretty(item))
  end

  local next_due_1 = to_date(item.nextDue[1], true)
  local next_due_2 = to_date(item.nextDue[2], true)
  --if item.text:find('Wool2') then
  --  declare('socket') declare('loadstring')
  --  declare('getfenv') declare('setfenv')
  --  local m = require('mobdebug')
  --  m.start('192.168.3.93')
  --end
  local start_date = to_date(item.startDate, true)

  local history = item.history
  local last_history_item = history[#history]
  local last_history_date = to_date(last_history_item.date)


  if start_date > today then
    item.due = start_date
  elseif start_date == today and not (last_history_date == today and last_history_item.completed) then
    item.due = today
  elseif last_history_date == today and last_history_item.completed and not item.completed then
    item.due = today
  elseif item.completed then
    item.due = next_due_2
  else
    item.due = last_history_date
  end
end

table.sort(items, function(a, b)
  return a.due < b.due
end)

local final_items = { }

for i = 1, #items do
  local item = items[i]
  if item.due > today then
    break
  end
  local tag_names = { }
  for _, tag_id in ipairs(item.tags) do
    tag_names[#tag_names + 1] = tags[tag_id]
  end
  table.sort(tag_names)
  tag_names = table.concat(tag_names, ', ')
  tag_names = tag_names .. (' '):rep(25 - #tag_names)
  final_items[#final_items + 1] =
  {
    n = #final_items + 1;
    due = item.due;
    tag_names = tag_names;
    text = item.text;
    id = item.id;
    checklist = item.checklist;
  }

end

table.sort(final_items, function(a, b)
  if a.tag_names == b.tag_names then
    return a.text < b.text
  end

  return a.tag_names < b.tag_names
end)

for i = 1, #final_items do
  local item = final_items[i]

  local prefix, suffix
  if today_ignores[item.id] then
    prefix = gray
    suffix = reset_color
  else
    prefix = ''
    suffix = ''
  end

  local tag_names = item.tag_names
  local color_tag = function(name, color)
    tag_names = tag_names:gsub(name, color .. name .. reset_color)
  end
  color_tag('pay', light_red)
  color_tag('evening', light_blue)
  color_tag('eat', light_yellow)
  color_tag('outdoor', gray)

  print(prefix .. item.due, tag_names, '[' .. i .. '] ' .. item.text .. suffix)

  if is_full and item.checklist then
    for j = 1, #item.checklist do
      local checklist_item = item.checklist[j]
      print('', '', tag_names, '    ' .. (checklist_item.completed and '[x]' or '[ ]'), checklist_item.text)
    end
  end
end

local f = io.open(FINAL_ITEMS_FILENAME, 'w')
f:write('return ' .. tstr(final_items))
f:close()
