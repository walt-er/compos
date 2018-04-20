-- =======================================================
-- generic globals
-- =======================================================

compos, debugging, win_w, win_h, win_l, win_r, win_t, win_b, tile, cam, player, player_states = {}, true, 128, 128, 0, 128, 0, 128, 8, {}, {}, {}

-- ======================================z=================
-- helper functions
-- =======================================================

-- deep copy tables or other values
-- by harraps
-- https://www.lexaloffle.com/bbs/?tid=2951
function copy(o)
    local c
    if type(o) == 'table' then
        c = {}
        for k, v in pairs(o) do
            c[k] = copy(v)
        end
    else
        c = o
    end
    return c
end

function ceil(num)
    return flr(num+0x0.ffff)
end

function vec(x,y)
    return { x=x, y=y }
end

function obj(x,y,w,h)
    return { x=x,y=y,w=w,h=h }
end

function split(string, char)
    local char = char or ','
	data={''}
	for i = 1, #string do
		local d=sub(string,i,i)
		if d == char then
			add(data,'')
		elseif d ~= ' ' then
			data[#data] = data[#data]..d
		end
	end
	return data
end

function rndval(t)
    return t[max(1, ceil(rnd(#t)))]
end

function combine(table1, table2)
    for k,v in pairs(table2) do
        if type(k) == 'string' then
            table1[k] = v
        else
            add(table1, v)
        end
    end
    return table1
end

-- functions for "physical" objects

function resize(thing, w, h)
    if h then
        -- rects take two values
        thing.w, thing.h = w, h
    else
        -- circles take one value
        thing.r, thing.w, thing.h = w, w, w
    end
end

function translate(thing, x, y)
    -- translate works for both circles and rects
	thing.x, thing.y = x, y
end

-- =======================================================
-- actor helpers
-- =======================================================

local actors, visible_actors, to_remove, update_pool, stages, update_id = {}, {}, {}, {}, split'state_update, early_update, update, late_update, fixed_update, background_draw, early_draw, draw, late_draw', 1

function reset_update_pool()
	update_pool = {}
	for stage in all(stages) do
		update_pool[stage] = {
			array = {},
			lookup = {}
		}
	end
end

function register(actor, parent)
    parent = parent or actor

	for stage in all(stages) do
		if actor[stage] then
			local stage_pool = update_pool[stage]

            -- save registration id on actor
			if (not(actor.update_ids)) actor.update_ids = {}
			actor.update_ids[stage..'_id'] = update_id

            -- save actor and reference to parent to update pools
			local registrant = {actor, parent}
            add(stage_pool.array, registrant)
            stage_pool.lookup[''..update_id] = registrant

            update_id += 1

        end
	end
end

function unregister(actor)
	for stage in all(stages) do
		if actor[stage] then
			local stage_pool = update_pool[stage]
			local id = ''..actor.update_ids[stage..'_id']
			local registrant = stage_pool.lookup[id]
			del(stage_pool.array, registrant)
			stage_pool.lookup[id] = nil
        end
	end
end

-- all actors have "physical" properties for size and location
function make_physical(thing)
	thing.x, thing.y, thing.w, thing.h = thing.x or 0, thing.y or 0, thing.w or tile, thing.h or tile
end

function init_actor(actor)
    -- add default properties for x, y, w, and h
	make_physical(actor)

    -- register actor update/draw function
    register(actor)

    -- initialize and register all compos on actor
	for k, compo_name in pairs(actor) do
        local compo = compos[compo_name]
		if compo then
            actor[compo_name] = copy(compo)
			if (compo.init) actor[compo_name]:init(actor)
			register(actor[compo_name], actor)
		end
	end

    -- run actor init function once compos are initialized
    if (actor.init) actor:init()

	-- default to 'in frame' for actors with no position
	actor.in_frame = true
end

function add_actor(actor)
	init_actor(actor)
    add(actors, actor)
end

function remove_actor(actor)
    unregister(actor)

	for k, compo in pairs(actor) do
		if type(compo) == 'table' then
			unregister(compo)
		end
	end

    del(actors, actor)
end

-- =======================================================
-- lifecycle management
-- =======================================================

-- to go in _init()
function compos_init()
	set_transparent_colors()
	reset_update_pool()
	for actor in all(actors) do
		init_actor(actor)
	end
end

-- to go in _update()
function compos_update()

	-- reset logs and limit permalogs
    -- remove for prod
    if debugging then
        logs, new_permalogs = {}, {}
        for i = 1, 15 do
            log(permalogs[i])
            add(new_permalogs, permalogs[i])
        end
        permalogs = new_permalogs
    end

	-- loop over all actors to determine if in frame
    visible_actors = {};
	for actor in all(actors) do

		-- only loop over (nearly) visible actors
		if cam.x and actor.x and not(actor.fixed) and not(actor.age) then
            local actor_x = actor.adjusted_x or actor.x
            local actor_y = actor.adjusted_y or actor.y

			actor.in_frame = actor_x + actor.w >= cam.x - win_w * 0.1
                and actor_x <= cam.x + win_w * 1.1
                and actor_y + actor.h >= cam.y - win_h * 0.1
                and actor_y <= cam.y + win_h * 1.1
		end

		if (actor.in_frame) add(visible_actors, actor)

	end

	-- run updates on actors and props that have registered to update
	for i = 1, #stages - 3 do -- don't include draw stages
		local stage = stages[i]
		for k, actor in pairs(update_pool[stage].array) do
			if (actor[2].in_frame ~= false) actor[1][stage](actor[1], actor[2])
		end
	end

	-- remove objects
	for i = 1, #to_remove do
		remove_actor(to_remove[i])
	end
	to_remove = {}

end

-- to go in _draw()
-- don't forget to run cls() first
function compos_draw()

	-- run draw on actors and props that have registered to draw
	for i = #stages - 3, #stages do -- only include draw stages
		local stage = stages[i]
		for k, actor in pairs(update_pool[stage].array) do
			if (actor[2].in_frame ~= false) actor[1][stage](actor[1], actor[2])
		end
	end

    -- debug logs
    if debugging then
        -- reset for logging
        camera()

        for i = 1, #logs do
            outline_print(logs[i], 5, 5 + ((i - 1) * tile), 7)
        end

        -- stats
        if show_stats then
            outline_print('mem: '..stat'0', 72, 5, 7)
            outline_print('fps: '..stat'7', 72, 13, 7)
        end
    end

end
