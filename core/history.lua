module 'aux.core.history'

include 'T'
include 'aux'

local persistence = require 'aux.util.persistence'
local info = require 'aux.util.info'

local history_schema = {'tuple', '#', {next_push='number'}, {daily_min_buyout='number'}, {data_points={'list', ';', {'tuple', '@', {value='number'}, {time='number'}}}}}

local value_cache = T

local commonMultipler = 4.44
local uncommonMultipler = 11
local rareMultipler = 22.22
local epicMultiplier = 40
local recipesMultipler = 8.88
local tradeGoodsMultipler = 8.88
local miscMultipler = 8.88


do
	local temp_cache
	function get_data()
		if not temp_cache then
			local dataset = persistence.dataset
			temp_cache = dataset.history or T
			dataset.history = temp_cache
		end
		return temp_cache
	end
end

do
	local temp_cache = 0
	function get_next_push()
		if time() > temp_cache then
			local date = date('*t')
			date.hour, date.min, date.sec = 24, 0, 0
			temp_cache = time(date)
		end
		return temp_cache
	end
end

function get_new_record()
	return O('next_push', next_push, 'data_points', T)
end

function read_record(item_key)
	local record = temp-(data[item_key] and persistence.read(history_schema, data[item_key]) or new_record)
	if record.next_push <= time() then
		push_record(record)
		write_record(item_key, record)
	end
	return record
end

function write_record(item_key, record)
	data[item_key] = persistence.write(history_schema, record)
	if value_cache[item_key] then
		release(value_cache[item_key])
		value_cache[item_key] = nil
	end
end

function M.process_auction(auction_record)
	local item_record = read_record(auction_record.item_key)
	local unit_buyout_price = ceil(auction_record.buyout_price / auction_record.aux_quantity)
	-- Saving the highest valued items instead of the lowest - daily_min_buyout is the wrong name now, but not going to bother changing it throughout the entire mod.
	if unit_buyout_price > 0 and unit_buyout_price > (item_record.daily_min_buyout or 0) then
	-- if unit_buyout_price > 0 and unit_buyout_price < (item_record.daily_min_buyout or huge) then
		item_record.daily_min_buyout = unit_buyout_price
		write_record(auction_record.item_key, item_record)
	end
end

function M.data_points(item_key)
	return read_record(item_key).data_points
end

function M.value(item_key)
	local value = calculate_adamino_max_value(item_key)
	
	if value == nil or value <= 0 then
		value = get_max_seen_ah_value(item_key)
	end

	if value and value > 0 then
        return value - 1
    end
end

function calculate_adamino_max_value(item_key)
    local item = info.item(item_key)
	local item_id = _G.aux_item_ids[strlower(item.name)]
	local vendor_price = _G.aux_merchant_sell[item_id]
    local item_qual = item.quality
    local item_class = item.class
    local item_sub_class = item.subclass

	-- SendChatMessage("item_id: " .. item_id,"SAY" ,"COMMON")
	-- SendChatMessage("Vendor price: " .. serializeTable(vendor_price) ,"SAY" ,"COMMON");
    -- SendChatMessage("Item: " .. serializeTable(item) ,"SAY" ,"COMMON")
    -- SendChatMessage("Item qual: " .. item_qual ,"SAY" ,"COMMON")
    -- SendChatMessage("Item class: " .. item_class ,"SAY" ,"COMMON")
    -- SendChatMessage("Item subclass: " .. item_sub_class ,"SAY" ,"COMMON")

    if vendor_price and vendor_price > 0 then
        if item_qual == 1 then return vendor_price * commonMultipler
        elseif item_qual == 4 then return vendor_price * epicMultiplier
        elseif item_class == "Recipe" then return vendor_price * recipesMultipler
        elseif item_class == "Trade Goods"  then return vendor_price * tradeGoodsMultipler
        elseif item_class == "Reagent"  then return vendor_price * tradeGoodsMultipler
        elseif item_sub_class == "Miscellaneous" then return vendor_price * miscMultipler
        elseif item_qual == 2 then return vendor_price * uncommonMultipler
        elseif item_qual == 3 then return vendor_price * rareMultipler        
        end
    end
end

function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then tmp = tmp .. name .. " = " end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp =  tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end

function get_max_seen_ah_value(item_key)
	if not value_cache[item_key] or value_cache[item_key].next_push <= time() then
		local item_record
		local value = 0
		item_record = read_record(item_key)
		if getn(item_record.data_points) > 0 then
			-- Always selecting the highest sell value, this is a bit volatile if other users gets involved, but as long as the bot is the only seller, it will work.
			for _, data_point in item_record.data_points do
				if data_point.value > value then value = data_point.value end
			end
		else
			value = item_record.daily_min_buyout
		end
		value_cache[item_key] = O('value', value, 'next_push', item_record.next_push)
	end
	return value_cache[item_key].value
end

function M.market_value(item_key)
	return value(item_key)
end

function weighted_median(list)
	sort(list, function(a,b) return a.value < b.value end)
	local weight = 0
	for _, element in ipairs(list) do
		weight = weight + element.weight
		if weight >= .5 then
			return element.value
		end
	end
end

function push_record(item_record)
	if item_record.daily_min_buyout then
		tinsert(item_record.data_points, 1, weak-O('value', item_record.daily_min_buyout, 'time', item_record.next_push))
		while getn(item_record.data_points) > 11 do
			release(item_record.data_points[getn(item_record.data_points)])
			tremove(item_record.data_points)
		end
	end
	item_record.next_push, item_record.daily_min_buyout = next_push, nil
end