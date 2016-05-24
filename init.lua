--[[

Copyright (C) 2016 Aftermoth, Zolan Davis

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation; either version 2.1 of the License,
or (at your option) version 3 of the License.

http://www.gnu.org/licenses/lgpl-2.1.html


--]]
--------------------------------------------------- Global

droplift = {
	invoke,
	-- function (dropobj, sync)
	-- sync in [ false | 0 | seconds ]. See details.txt
}

--------------------------------------------------- Local

-- minetest.get_us_time is not defined in 0.4.10
local seconds = 0.0
if not minetest.get_us_time then
	minetest.register_globalstep(function(dtime)
				seconds = seconds + dtime
			end)
	minetest.get_us_time = function()
		return seconds * 1000000
	end
end

local function obstructed(p)
	local n = minetest.get_node_or_nil(p)
	return n and minetest.registered_nodes[n.name].walkable
end


-- * Local escape *

local function near_player(dpos)
	local near = 8.5
	local pp, d, ppos
	for _,player in ipairs(minetest.get_connected_players()) do
		pp = player:getpos()
		pp.y = pp.y + 1
		d = math.abs(pp.x-dpos.x) + math.abs(pp.y-dpos.y) + math.abs(pp.z-dpos.z)
		if d < near then
			near = d
			ppos = pp
		end
	end
	return ( near < 8.5 and ppos )
end

local function usign(r)
	return ( r < 0 and -1 ) or 1
end

local function escape(ent,pos)
	local bias = {x = 1, y = 1, z = 1}
	local o = {a="x", b="y", c="z"}
	local pref = near_player(pos)
	if pref then
		bias = {x = usign(pref.x - pos.x), y = usign(pref.y - pos.y), z = usign(pref.z - pos.z)}
		local mag={x = math.abs(pref.x - pos.x), y = math.abs(pref.y - pos.y), z = math.abs(pref.z - pos.z)}
		if mag.z > mag.y then
			if mag.y > mag.x then
				o={a="z",b="y",c="x"}
			elseif mag.z > mag.x then
				o={a="z",b="x",c="y"}
			else
				o={a="x",b="z",c="y"}
			end
		else
			if mag.z > mag.x then
				o={a="y",b="z",c="x"}
			elseif mag.y > mag.x then
				o={a="y",b="x",c="z"}
			end
		end
	end

	local p
	for a = pos[o.a] + bias[o.a], pos[o.a] - bias[o.a], -bias[o.a] do
		for b = pos[o.b] + bias[o.b], pos[o.b] - bias[o.b], -bias[o.b] do
			for c = pos[o.c] + bias[o.c], pos[o.c] - bias[o.c], -bias[o.c] do
				p = {[o.a]=a, [o.b]=b, [o.c]=c}
				if not obstructed(p) then
					ent.object:setacceleration({x=0,y=-10,z=0})
					ent.object:setpos(p)
					return p
				end
			end
		end
	end

	return false
end


-- * Entombment physics *

-- ---------------- LIFT

local function lift(obj)
	local p = obj:getpos()
	if p then
		local ent = obj:get_luaentity()
		if ent.is_entombed and obstructed(p) then
-- Time
			local t = 1
			local s1 = ent.sync1
			if s1 then
				local sd = ent.sync0+s1-minetest.get_us_time()
				if sd > 0 then t = sd/1000000 end
				ent.sync0, ent.sync1 = nil, nil
			end
-- Space
			p = {x = p.x, y = math.floor(p.y - 0.5) + 1.800001, z = p.z}
			obj:setpos(p)
			if s1 or obstructed(p) then
				obj:setvelocity({x = 0, y = 0, z = 0})
				obj:setacceleration({x = 0, y = 0, z = 0})
				minetest.after(t, lift, obj)
				return
			end
		end -- if w
-- Void.
		ent.is_entombed, ent.sync0, ent.sync1 = nil, nil, nil
	end  -- if p
end

-- ---------------- ASYNC

local counter = function()
	local k = 0
	return function()
				k = (k==9973 and 1) or k+1
				return k
			end
end
local newhash = counter()

local function async(obj, usync)
	local p = obj:getpos()
	if p then
		local ent = obj:get_luaentity()
		local hash = newhash()
		ent.hash = ent.hash or hash
		if obstructed(p) then
-- Time.
			if not usync then
				if escape(ent, p) and  hash == ent.hash then
					ent.hash = nil
				end
			elseif usync > 0 then
				ent.sync0 = minetest.get_us_time()
				ent.sync1 = usync
			end
-- Space.
			if hash == ent.hash then
				obj:setpos({x = p.x, y = math.floor(p.y - 0.5) + 0.800001, z = p.z})
				obj:setvelocity({x = 0, y = 0, z = 0})
				obj:setacceleration({x = 0, y = 0, z = 0})
				if not ent.is_entombed then
					ent.is_entombed = true
					minetest.after(1, lift, obj)
				end
			end
		end -- if w
		if hash == ent.hash then ent.hash = nil end
	end  -- if p
end

droplift.invoke = function(obj, sync)
	async(obj, (sync and math.max(0,sync)*1000000))
end


-- * Events *

local function append_to_core_defns()
	local dropentity=minetest.registered_entities["__builtin:item"]

	-- Ensure consistency across reloads.
	local on_activate_copy = dropentity.on_activate
	dropentity.on_activate = function(ent, staticdata, dtime_s)
		on_activate_copy(ent, staticdata, dtime_s)
		if staticdata ~= "" then 
			if minetest.deserialize(staticdata).is_entombed then
				ent.is_entombed = true
				minetest.after(0.1, lift, ent.object)
			end
		end
		ent.object:setvelocity({x = 0, y = 0, z = 0})
	end

	-- Preserve state across reloads
	local get_staticdata_copy = dropentity.get_staticdata
	dropentity.get_staticdata = function(ent)
		local s = get_staticdata_copy(ent)
		if ent.is_entombed then
			local r = {}
			if s ~= "" then
				r = minetest.deserialize(s)
			end
			r.is_entombed=true
			return minetest.serialize(r)
		end
		return s
	end

	-- Update drops inside newly placed nodes.
	local add_node_copy = minetest.add_node
	minetest.add_node = function(pos,node)
		add_node_copy(pos, node)
		local a = minetest.get_objects_inside_radius(pos, 0.87)
		for _,obj in ipairs(a) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "__builtin:item" then
				async(obj)
			end
		end
	end

end


append_to_core_defns()
