pico-8 cartridge // http://www.pico-8.com
version 14
__lua__
-- tuck and rolo

-- use picotool's require() function to include this lua script

-- =======================================================
-- generic globals
-- =======================================================

compos, win_w, win_h, win_l, win_r, win_t, win_b, tile, cam, player, player_states = {}, 128, 128, 0, 128, 0, 128, 8, {}, {}, {}

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

function split(string)
	data={''}
	for i = 1, #string do
		local d=sub(string,i,i)
		if d == ',' then
			add(data,'')
		elseif d ~= ' ' then
			data[#data] = data[#data]..d
		end
	end
	return data
end

-- =======================================================
-- debugging helpers (remove for prod)
-- =======================================================

logs, permalogs, show_colliders, show_stats, log_states, log_statuses = {}, {}, false, true, false, false

function reverse(table)
    for i=1, flr(#table / 2) do
        table[i], table[#table - i + 1] = table[#table - i + 1], table[i]
    end
end

function unshift(array, value)
    reverse(array)
    add(array, value)
    reverse(array)
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

function log(message)
    add(logs, message)
end

function plog(message)
    unshift(permalogs, message)
end

-- =======================================================
-- state helpers
-- =======================================================

function trigger_state(state, actor, states)
	-- default to player
	actor = actor or player
	states = states or player_states

	-- run new state
    if states[state] then
        actor.state = states[state]
        actor.state(actor, states)
    end

    return
end

-- =======================================================
-- drawing helpers
-- =======================================================

local transparent = 11 -- change this to whatever color you use as transparent in your sprites
function set_transparent_colors()
	pal()
    palt(0, false)
    palt(transparent, true)
end

function outline_print(s, x, y, color, outline)
	outline = outline or 0
    for i = -1, 1 do
        for j = -1, 1 do
            if not(i == j) then
                print(s,x+i,y+j,outline)
            end
        end
    end
    print(s, x, y, color)
end

function outline_rect(x, y, x2, y2, fill, outline)
    outline = outline or 0
    rectfill(x, y-1, x2, y2+1, outline)
    rectfill(x-1, y, x2+1, y2, outline)
    rectfill(x, y, x2, y2, fill)
end

function outline_circ(x, y, r, fill, outline)
    outline = outline or 0
    circfill(x,y,r+1,outline)
    circfill(x,y,r,fill)
end

-- zoom a sprite to fill an area
function zspr(n, dx, dy, w, h, flip_x, flip_y, dz)
	if not(dz) or dz==1 then
		spr(n,dx,dy,w,h,flip_x,flip_y)
    elseif n >= 0 then
        sx, sy, sw, sh = shl(band(n, 0x0f), 3), shr(band(n, 0xf0), 1), shl(w, 3), shl(h, 3)
		dw, dh = sw * dz, sh * dz
        sspr(sx,sy,sw,sh,dx,dy,dw,dh,flip_x,flip_y)
    end
end

function outline_spr(id, x, y, w, h, outline, fill, flip_x, flip_y, zoom)

    -- don't outline
	if outline == -1 then
        set_transparent_colors()
        zspr(id, x, y, w, h, flip_x, flip_y, zoom)
	else

        -- change all colors to outline color
        outline = outline or 0
        for i=1, 15 do
            if (i ~= transparent) pal(i, outline)
        end

        -- draw outline sprites
        for i = -1, 1 do
            for j = -1, 1 do
                if not(abs(i) == abs(j)) then
                    zspr(id, x+i, y+j, w, h, flip_x, flip_y, zoom)
                end
            end
        end

        -- fill sprite or draw full color sprite on top of outline
        if fill then
            -- change all colors to fill color
            for i=0, 15 do
                if (i ~= transparent) pal(i, fill)
            end
            zspr(id, x, y, w, h, flip_x, flip_y, zoom)
            set_transparent_colors()
        else
            set_transparent_colors()
            zspr(id, x, y, w, h, flip_x, flip_y, zoom)
        end
    end
end

-- fill with sprite pattern (not 100% accurate?)
function spritefill(rectangle, id, pattern_width)
	pattern_width = pattern_width or 1;
	for i = 0, flr(rectangle.w / (tile * pattern_width)) - 1 do
		for j = 0, flr(rectangle.h / (tile * pattern_width)) - 1 do
			spr(id, rectangle.x + (i * (tile * pattern_width)), rectangle.y + (j * (tile * pattern_width)))
		end
	end
end


-- =======================================================
-- actor helpers
-- =======================================================

local actors, visible_actors, to_remove, update_pool, stages, update_id = {}, {}, {}, {}, split'early_update, update, late_update, fixed_update, early_draw, draw', 1

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
-- =======================================================
-- components (compos!)
-- =======================================================
-- =======================================================

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

--

compos.health = {
    total = -999,
    max = 0,
    set = function(self, new_health)
        self.max, self.total = max(0, new_health), max(0, new_health)
    end,
    damage = function(self, damage)
        self.total, self.damage_time = self.total - damage, time()
    end,
    update = function(self, parent)

        -- store life as flag on parent, call death function
        parent.alive = self.total > 0
		if (self.total ~= -999 and not(parent.alive) and parent.die) parent:die()

        -- show health bar when damaged
        self.show_health = self.damage_time and time() - self.damage_time < 2 and parent.alive

    end,
    draw = function(self, parent)
        if self.show_health and self.total > 0 then

            -- calculate position of health bar to draw
            local start_x, start_y, end_x, end_y = parent.x - 2, parent.y - 8, parent.x + parent.w + 2, parent.y - 6

            -- get end x for fill representing remaining health
            local fill_end_x = start_x + flr((end_x - start_x) * (self.total / self.max))

            -- draw health bar
            outline_rect(start_x, start_y, end_x, end_y, 6, 1)
            line(start_x, end_y, end_x, end_y, 13)
            outline_rect(start_x, start_y, fill_end_x, end_y, 8)
            line(start_x, start_y, fill_end_x, start_y, 14)

        end
    end
}

function hurt(actor, attack)
    if
		attack.armed
        and actor.health
        and actor.health.total > 0
    then

        -- if valid target, hurt actor and remove attack object
        actor.health:damage(attack.damage)
        if (actor.sprite and actor.health.total > 0) actor.sprite:flash()
		attack.armed = false

    end
end

function throw(actor, newvec, distance)
	distance = distance or 2
    local flip = player.flip_x or 1
	local throwvec = vec(flip * distance, -distance)
	actor.velocity:set(throwvec.x, throwvec.y)
	actor.thrown = true
	return vec(newvec.x + throwvec.x, newvec.y + throwvec.y)
end

--

compos.velocity = {
    x = 0,
    y = 0,
    max_x = 999,
    max_y = 999,
    decay = vec(1, 1),
    newvec = vec(0, 0),
    set = function(self, x, y, decay)
        self.x, self.y = x, y
        if (decay) self.decay = decay
    end,
    accelerate = function(self, x_acceleration, y_acceleration)
        self.x += x_acceleration
        self.y += y_acceleration
    end,
    cap = function(self, x, y)
        self.max_x, self.max_y = x, y
    end,
    update = function(self, parent)

        self.x, self.y = mid(self.x, -self.max_x, self.max_x), mid(self.y, -self.max_y, self.max_y)

        -- get new set of coordinates using current velocity (don't apply yet)
        self.newvec = vec(parent.x + self.x, parent.y + self.y)

        --decay
        self.x *= self.decay.x
        self.y *= self.decay.y

    end,
    fixed_update = function(self, parent)

        -- apply velocity after all collisions
        translate(parent, self.newvec.x, self.newvec.y)

    end
}

function collision_direction(col1, col2)
    local direction = ''

    local left_overlap, right_overlap, bottom_overlap, top_overlap = col1.x > col2.x + col2.w, col1.x + col1.w < col2.x, col1.y + col1.h < col2.y, col1.y > col2.y + col2.h

    if top_overlap then
        direction = 'top'
    elseif bottom_overlap then
        direction = 'bottom'
    elseif right_overlap then
        direction = 'right'
    elseif left_overlap  then
        direction = 'left'
    end

    -- if no direction, retry with smaller colliders
    if direction == '' and col1.w > 2 and col1.h > 2 and col2.w > 2 and col2.h > 2 then
		local new_col1, new_col2 = obj(col1.x + 1, col1.y + 1, col1.w - 2, col1.h - 2), obj(col2.x + 1, col2.y + 1, col2.w - 2, col2.h - 2)
        return collision_direction(new_col1, new_col2)
    else
        return direction
    end
end

-- distance between two points
-- by freds72
-- https://www.lexaloffle.com/bbs/?pid=49926#p49926
function sqrdist(obj1, obj2)
    return (obj1.x-obj2.x)^2+(obj1.y-obj2.y)^2
end

function overlapping_rects(obj1, obj2)
	local x = obj1.x + obj1.w >= obj2.x and obj1.x <= obj2.x + obj2.w
	local y = obj1.y + obj1.h >= obj2.y and obj1.y <= obj2.y + obj2.h
	return x and y
end

function check_collision(parent, other)

    -- only continue if this isn't the parent collider
        -- only take action if colliders overlap
    if other.collider and other.id ~= parent.id then

        -- get new collider positions based on current parent velocity
        -- define objects to represent colliders at new positions
        local parent_pos, other_pos = parent.velocity and parent.velocity.newvec or parent, other.velocity and other.velocity.newvec or other
        local parent_col = obj(
            parent_pos.x + parent.collider.offset.x,
            parent_pos.y + parent.collider.offset.y,
            parent.collider.w,
            parent.collider.h
        )
        local other_col = obj(
            other_pos.x + other.collider.offset.x,
            other_pos.y + other.collider.offset.y,
            other.collider.w,
            other.collider.h
        )

        -- check if colliders overlap
        if overlapping_rects(parent_col, other_col) then

            if parent.velocity then

                -- run gravity collision with objects below
                -- run collision calculations on parent object if needed
                if (parent.gravity and not(parent.thrown) and other.is_ground) parent.velocity.newvec = trigger_grounding(parent, other, parent.velocity.newvec)
                if (parent.collision) parent.velocity.newvec = parent:collision(parent.velocity.newvec, other)

            elseif parent.static_collision then

                -- collider function that doesn't return a new position
                parent:static_collision(other)

            end
        end
    end
end

collider_id = 0
compos.collider = {
    offset = vec(0, 0),
    set = function(self, parent, offset, w, h, r)

        -- set size and offset from parent
        self.offset = offset or vec(0, 0)
        self.w, self.h, self.r = w or parent.w, h or parent.h, r or parent.r

        -- add to array of colliders
        parent.id = parent.id or collider_id
        collider_id += 1

    end,
    late_update = function(self, parent)

        -- reset gravity, only set grounded to true if colliding with ground
        if parent.gravity then
            parent.grounded, parent.thrown = false, false
        end

        -- loop over all colliders if parent has collider
        -- the ground never starts a collision
        if parent.collision and not(parent.is_ground) then

			-- permanent colliders
			for actor in all(visible_actors) do
				check_collision(parent, actor)
			end
		end
    end,

    draw = function(self, parent)
        if show_colliders then
            if parent.r then
                circ(parent.x + self.offset.x, parent.y + self.offset.y, self.r, 11)
            else
                rect(parent.x + self.offset.x, parent.y + self.offset.y, parent.x + self.offset.x + self.w, parent.y + self.offset.y + self.h, 11)
            end
        end
    end
}

--

compos.gravity = {
    force = 1,
    set = function(self, force)
        self.force = force
    end,
    early_update = function(self, parent)
        parent.velocity.y += self.force
    end
}

function trigger_grounding(parent, other, newvec)

    local direction = collision_direction(parent, other)
    if direction == 'bottom' then
        parent.grounded = true
        parent.velocity.y = min(0, parent.velocity.y)
        newvec.y = other.y + other.collider.offset.y - parent.h
    end

    return newvec

end

--

compos.sprite = {
	id = 0,
    loop = false,
    zoom = 1,
    animating = false,
    frame = 0.1,
    flipped = false,
	flip_y = false,
    flash_count = -1,
	outline = 0,
    old_fill = -1,
    old_outline = -1,

    set = function(self, id, size, zoom)
        self.id = id
		if (size) then
			self.w = size.x
			self.h = size.y
		end
		self.zoom = zoom
    end,

    animate = function(self, parent, spritesheet, fps, loop, zoom)
        self.animating, self.loop, self.sheet, self.frame, self.fps, self.zoom, self.t = true, loop, spritesheet, 0.1, fps, zoom ~= nil and zoom or 1, time()
    end,

    stop_animation = function(self)
        self.sheet, self.animating = {}, false
    end,

    flash = function(self, color, outline, count, frame_length)
        self.flashes, self.flashing, self.flash_color, self.flash_outline, self.flash_frame_length = 0, false, color or 8, outline or 2, frame_length or 3
		self.flash_count = count or self.flash_frame_length
    end,

    reset_flash = function(self)
        self.fill, self.outline, self.flashing, self.old_fill, self.old_outline, self.flash_count = self.old_fill, self.old_outline, false, -1, -1, -1
    end,

    update = function(self, parent)

		local sheet = self.sheet

        -- loop over spritesheet if it exists
        if sheet and #sheet > 0 then

            -- iterate over frames
            local frame = (time() - self.t) * self.fps
            frame = self.loop and frame % #sheet or min(#sheet, frame)

            -- set new frame
            self.id = sheet[max(1, ceil(frame))]

            -- stop animation (if not looping) at end of sheet
            if (not(self.loop) and frame >= #sheet) self:stop_animation()

        end

        -- flash
        if self.flash_count > -1 and self.flashes < self.flash_count then
            if not(self.flashing) then

                if (self.old_fill == -1) then
                    self.old_fill = self.fill ~= nil and self.fill + 0 or nil
                    self.old_outline = self.outline + 0 or nil
                end

                self.fill = self.flash_color
                self.outline = self.flash_outline
                self.flashes += 1
                if (self.flashes % self.flash_frame_length == 0) self.flashing = true
            else
                self:reset_flash()
            end
        elseif self.flash_count ~= -1 then
            self:reset_flash()
        end

    end,

	draw_sprite = function(self, parent)
		self.w = self.w or parent.w
		self.h = self.h or parent.h
		self.zoom = self.zoom or 1

        -- render selected sprite at position
		local spr_x = parent.x + (parent.w / 2) - (self.w / 2)
		local spr_y = parent.y + (parent.h / 2) - (self.h / 2)
        outline_spr(self.id, spr_x, spr_y, (self.w / tile) / self.zoom, (self.h / tile) / self.zoom, self.outline, self.fill, self.flipped, self.flip_y, self.zoom)
	end,

	early_draw = function(self, parent)
		if (parent.background) self.draw_sprite(self, parent);
	end,

    draw = function(self, parent)
		if (not(parent.background)) self.draw_sprite(self, parent);
    end
}

--

compos.age = {
    set = function(self, death)
        self.birth = time()
        self.death = death
    end,
    update = function(self, parent)
        if self.birth and time() - self.birth > self.death then
            remove_actor(parent)
        end
    end,
}

--

compos.patrol = {
    start = vec(0, 0),
    target = vec(0, 0),
    tick = 0,
    step = 0,
    duration = 0,
    fixed = false,
    direction = 'going',

    set = function(self, start, target, duration, step, fixed)
        self.start, self.target, self.duration, self.step, self.fixed, self.returning = start, target, duration, step, fixed, false
    end,

    flip = function(self, parent)

        -- turn around
        self.returning = not(self.returning)
        parent.sprite.flipped = self.returning

        -- remain in patrol area if fixed, otherwaise restart tick
        self.tick = self.fixed and self.duration - self.tick or 0

    end,

    early_update = function(self, parent)
        if not(parent.alive) then

            -- stop patrol on death
            parent.velocity.x = 0

        else

            -- up counter and calculate progress
            self.tick += self.step
            local progress = self.tick / self.duration

            -- get distance chunk
            local time_chunk = self.duration / self.step
            local distance_chunk = abs(self.target.x - self.start.x) / time_chunk

            -- calculate velocity
            if (parent.grounded) parent.velocity.x = self.returning and distance_chunk or -distance_chunk

            -- set sprite direction
            parent.sprite.flipped = self.returning

            -- reverse when reaching end
            if self.tick >= self.duration then
                self.tick = 0
                self.returning = not(self.returning)
            end

        end
    end
}


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
	logs, new_permalogs = {}, {}
	for i = 1, 15 do
		log(permalogs[i])
		add(new_permalogs, permalogs[i])
	end
	permalogs = new_permalogs

	-- loop over all actors to determine if in frame
    visible_actors = {};
	for actor in all(actors) do

		-- only loop over (nearly) visible actors
		if cam.x and actor.x and not(actor.fixed) then
			actor.in_frame = actor.x + actor.w >= cam.x - win_w * 0.1
                and actor.x <= cam.x + win_w * 1.1
                and actor.y + actor.h >= cam.y - win_h * 0.1
                and actor.y <= cam.y + win_h * 1.1
		end

        -- state machines
		if actor.in_frame then

            add(visible_actors, actor)

			-- create state machines if needed
			if (actor.state == nil and actor.default_state) actor.state = actor.default_state
			if (actor.status == nil and actor.default_status) actor.status = actor.default_status

			---------------------
			-- run state machines
			---------------------
			if (actor.state) actor.state(actor, actor.state_list)
			if (actor.status) actor.status(actor, actor.status_list)

		end
	end

	-- run updates on actors and props that have registered to update
	for i = 1, #stages - 1 do -- don't include draw stages
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
	for i = #stages - 1, #stages do -- only include draw stages
		local stage = stages[i]
		for k, actor in pairs(update_pool[stage].array) do
			if (actor[2].in_frame ~= false) actor[1][stage](actor[1], actor[2])
		end
	end

    -- reset for logging
    camera()

	-- debug logs
	for i = 1, #logs do
		outline_print(logs[i], 5, 5 + ((i - 1) * tile), 7)
	end

	-- stats
	if show_stats then
		outline_print('mem: '..stat'0', 72, 5, 7)
		outline_print('fps: '..stat'7', 72, 13, 7)
	end
end


-- =======================================================
-- =======================================================
-- tuck and rolo
-- =======================================================
-- =======================================================


-- game props
local score = 0
local clear = true

-- actors
local game_actors = {}
local rolo = {}
local castle = {}
local ground = {}
local backdrop = {}

-- =======================================================
-- backdrop
-- =======================================================

function draw_background(override_camera)

	camera()

	-- draw sky
	local sky_color = 1
	rectfill(0, 0, win_w, win_h, sky_color)

	-- draw stars
	circ(43, 78, 1, 6)
	circ(100, 59, 1, 6)
	circ(71, 20, 1, 6)
	circ(18, 48, 1, 6)
	circ(90, 44, 1, 6)
	circ(110, 19, 1, 6)
	circ(20, 24, 1, 6)
	circ(33, 32, 1, 12)

	-- draw hills
	circfill(42, 159, 100, 3)
	circfill(40, 160, 100, 0)
	circfill(92, 169, 100, 3)
	circfill(90, 170, 100, 0)

	-- draw moon
	local moon_position_x = win_w - (tile * 4)
	local moon_position_y = tile * 3
	outline_spr(14, moon_position_x, moon_position_y, 2, 2)

	-- draw moon crescent
	local level = 0
	circfill(moon_position_x - tile - 1 + (level * 3), moon_position_y + tile, tile, sky_color)

	if (not(override_camera)) cam_center()

end

-- -- clouds
-- for i = 1, 0 do
-- 	local cloud = {
-- 		w, h,
-- 		x = 0,
-- 		y = 0,
-- 		tick = 0,
-- 		speed = rnd(100) / 1500,

-- 		init = function(self)
-- 			resize(self, tile * 2, tile)
-- 			self.y_offset = rnd(4) * tile + 12
-- 			self.x_offset = rnd(win_w)
-- 		end,

-- 		update = function(self)

-- 			self.tick += 1
-- 			local new_x = flr((((self.tick * self.speed) + self.x_offset) % (win_w + (self.w * 2)))) - self.w
-- 			translate(self, new_x, self.y_offset)

-- 		end,

-- 		fixed_draw = function(self)
-- 			outline_spr(46, self.x, self.y, self.w / tile, self.h / tile)
-- 		end
-- 	}

-- 	add(game_actors, cloud)
-- end

-- castle = {
-- 	early_draw = function(self)

-- 		camera()

-- 		local wall_color = 0
-- 		local wall_color_light = 5
-- 		local moonlight_color = 13
-- 		local frame_color = 5

-- 		local offset_x = cam.x / 8
-- 		local win_gap = 16
-- 		local win_width = (win_w / 2) - win_gap
-- 		local window_top = tile
-- 		local window_bottom = tile * 10

-- 		-- horizontal
-- 		local horizontal_start = -offset_x % tile - tile
-- 		local horizontal_end = win_w + (-offset_x % tile)
-- 		rectfill(horizontal_start, 0, horizontal_end, window_top, wall_color)
-- 		rectfill(horizontal_start, window_bottom, horizontal_end, win_h, wall_color)

-- 		-- vertical
-- 		local total_windows = 4
-- 		for i = 0, total_windows do

-- 			local window_left = (((win_width + win_gap) * i) - offset_x) % (total_windows * (win_width + win_gap)) - (win_width + win_gap)
-- 			local window_right = window_left + win_width

-- 			rectfill(window_left - 1, -1, window_left - win_gap + 1, win_h, wall_color)
-- 			-- rect(window_left, -1, window_left - win_gap, win_h, 0)

-- 			line(window_left, window_top + ((window_bottom - window_top) / 2), window_right, window_top + ((window_bottom - window_top) / 2), frame_color)
-- 			line(window_left + ceil((window_right - window_left) / 2), window_top, window_left + ceil((window_right - window_left) / 2), window_bottom, frame_color)
-- 			rect(window_left, window_top, window_right, window_bottom, frame_color)

-- 			for j = window_left, window_right do
-- 				line(j, window_bottom + 1, j - 16, win_h, moonlight_color)
-- 			end

-- 		end

-- 		cam_center()

-- 	end
-- }
-- add(game_actors, castle)


-- =======================================================
-- ground
-- =======================================================

ground = {

	tag = 'ground',

	-- compos
	'collider',
	is_ground = true,
	fixed = true,

	init = function(self)
		resize(self, 160, win_h)
		translate(self, 0, 0)
		self.collider:set(self)
	end,

	update = function(self)
		translate(self, cam.x - 16 - cam.x % 16, 0)
	end,

	early_draw = function(self)
		spritefill(self,241)
		for i = 0, self.w do
			spr(225, self.x + i * tile, self.y)
		end
	end

}
add(game_actors, ground)

local prewall = {
	tag = 'prewall',
	'collider',

	x = -150,
	y = -128,
	w = 128,
	h = 128,

	init = function(self)
		self.collider:set(self)
	end,

	draw = function(self)
		spritefill(self, 241)
	end
}
add(game_actors, prewall)

local instructions = {
	{ '\139 and \145 to move', {-16, -36}},
	{ '\148 to jump', {84, -36}},
	{ '\142 to attack', {154, -36}},
	{ '\131 to block', {300, -72}},
	{ '\131+\142 to fire', {420, -72}},
	{ '\151 to dodge,', {550, -72}},
	{ '\131+\151 to dodge backwards', {550, -64}},
	{ 'good luck!', {750, -36}}
}

for i = 1, #instructions do
	local introtext = {
		init = function(self)
			local message = instructions[i];
			translate(self, message[2][1], message[2][2])
			resize(self, 4 * #message[1] + 8, 8)
		end,
		draw = function(self)
			outline_print(instructions[i][1], self.x, self.y, 7)
		end
	}
	add(game_actors, introtext)
end

-- =======================================================
-- player attacks
-- =======================================================

attack_sprites = split'62, 78, 94'

local attack = {

	tag = 'attack',

	'age',
	'collider',
	'sprite',

	is_attack = true,
	damage = 2,

	move = function(self)
		local new_x = p_flipped and player.x - self.w - 4 or player.x + player.w + 4
		translate(self, new_x, player.y + player.h / 2 - self.h / 2)
	end,

	init = function(self)

		self:move()

		resize(self, tile * 2, tile*1)
		self.collider:set(self)

		self.age:set(0.16)
		self.armed = true

		self.sprite.flipped = p_flipped
		self.sprite.flip_y = flr(rnd(2)) > 0
		self.sprite:animate(self, attack_sprites, 20)

	end,

	update = function(self)

		self.sprite.w = not(self.armed) and self.w or 0
		self.sprite.h = not(self.armed) and self.h or 0

	end

}

local bullet_sprites = split'13, 29, 45, 61'

local bullet = {

	'age',
	'velocity',
	'collider',
	'sprite',

	is_attack = true,
	damage = 1,
	flipped = 1,

	init = function(self)
		resize(self, 2, 10)
		self.sprite.w = tile
		self.sprite.h = tile
		translate(self, rolo.x + (rolo.w / 2) - (self.w / 2) + 1, rolo.y + (rolo.h / 2) - (self.h / 2))
		self.velocity:set(6 * self.flipped, 0)
		self.collider:set(self)
		self.age:set(1)

		self.armed = true

		if not(self.sprite.animating) then
			self.sprite.flipped = p_flipped
			self.sprite:animate(self, bullet_sprites, 15, true)
		end
	end,

	collision = function(self, newvec, other)
		if (not(self.armed)) add(to_remove, self)
		return newvec
	end
}

local death_sprites = split'57, 42, 43, 58, 59, 44, 60, -1'


-- =======================================================
-- player
-- =======================================================

player_states = {
	grounded = function(player, states)

		--------
		-- exits
		--------

		if player.grounded == false then

			-- fall
			trigger_state'falling'

		elseif btn'2' and player.can_jump then

			-- jump
			p_velocity:set(p_velocity.x * 1.2, player.jump)
			player.thrown = true
			trigger_state'jumping'

		elseif btn'5' and player.can_dodge then

			-- dodge forward
		 p_velocity:set(player.dodge_forward * player.flip_x, player.jump / player.dodge_damp)
			player.thrown = true
			trigger_state'dodging'

		elseif btn'3' then

			-- block
			trigger_state'blocking'

		elseif btn'4' and player.can_attack then

			-- attack
			trigger_state'attacking'

		else

			-------
			-- init
			-------

			if (player.last_state ~= 'grounded') then
				player.last_state = 'grounded'
			end

			----------------------
			-- run state functions
			----------------------

			-- if (log_states) log'grounded state'

			player.stunned = false

			-- movment
			if not(btn'0') and not(btn'1') then

				-- tick idle
				player.sprite:stop_animation()
				player.idle_frame = (player.idle_frame + player.idle_fps) % #player.idle_sprites
				player.sprite.id = player.idle_sprites[ ceil(player.idle_frame) ]
				p_velocity.x = 0

			else

				--running sprite
				if (not(player.sprite.animating)) player.sprite:animate(player, player.running_sprites, 12, true)

			end

			player.accel = player.default_accel
			p_velocity.decay.x = 0.75
			p_velocity:cap(2.1, player.jump)
			-- p_velocity.x *= 0
			player_move(player)

		end
	end,
	jumping = function(player, states)

		--------
		-- exits
		--------

		if player.grounded and not(player.thrown) then

			player.stunned = false
			trigger_state'grounded'

		elseif btn'5' and player.can_dodge then

			-- air dodge
			player.stunned = false
			p_velocity:set(player.dodge_forward * player.flip_x, player.jump / player.dodge_damp)
			trigger_state'dodging'

		else

			-------
			-- init
			-------

			if (player.last_state ~= 'jumping') then
				player.last_state = 'jumping'
				player.can_jump = false
			end

			----------------------
			-- run state functions
			----------------------

			-- if (log_states) log'jumping state'

			if (player.stunned) then
				player.accel = 0
				player.sprite.id = 5
			else
				player.accel = player.default_accel
				player.sprite.id = 3
			end

			p_velocity:cap(3.5, player.jump)
			p_velocity.decay.x = 0.75
			player_move(player)

		end
	end,
	dodging = function(player, states)

		--------
		-- exits
		--------

		if player.dodge_start and time() - player.dodge_start > player.dodge_length then
			player.dodge_start = nil
			player.dodging = false
			player.invincible = false
			trigger_state'grounded'
		else

			-------
			-- init
			-------

			if (player.last_state ~= 'dodging') then
				player.last_state = 'dodging'
				player.dodge_start = time()
				player.invincible = true
				player.can_dodge = false
			end

			----------------------
			-- run state functions
			----------------------

			-- if (log_states) log'dodging state'

			-- movement
			player.accel = 0
			player.sprite.id = 3
			p_velocity:cap(16, player.jump)
			p_velocity.decay.x = 1
			player_move(player)

		end
	end,
	blocking = function(player, states)

		--------
		-- exits
		--------

		if btn'5' and player.can_dodge then

			-- dodge backward
			p_velocity:set(-player.dodge_forward * player.flip_x, player.jump / player.dodge_damp)
			player.blocking = false
			player.thrown = true
			trigger_state'dodging'

		elseif not btn'3' then

			-- exit blocking state
			player.blocking = false
			trigger_state'grounded'

		else

			-------
			-- init
			-------

			if (player.last_state ~= 'blocking') then
				player.last_state = 'blocking'
				player.blocking = true
				player.sprite:animate(player, player.block_sprites, 30)
			end

			----------------------
			-- run state functions
			----------------------

			-- if (log_states) log'blocking state'

			-- fire
			if btn'4' and rolo.can_fire then
				rolo:fire()
			end

			-- movement
			player.accel = 1
		 	p_velocity.decay.x = 0
			player_move(player)

		end
	end,
	attacking = function(player, states)

		-------
		-- init
		-------

		if (player.last_state ~= 'attacking') then
			player.last_state = 'attacking'
			player.can_attack = false
			player.invincible = true
			player.attack_start = time()
			player.sprite:animate(player, player.attack_sprites, #player.attack_sprites / player.attack_length)

			p_velocity.x += player.flip_x * 1.5

			add_actor(copy(attack))
		end

		----------------------
		-- run state functions
		----------------------

		-- if (log_states) log'attacking state'

		player.attacking = true
		player.accel = 0
		p_velocity.decay.x = 1

		if (time() - player.attack_start) >= player.attack_length then

			player.attacking = false
			player.invincible = false
			trigger_state'grounded'

		end

	end,
	dead = function(player, states)

		if (player.last_state ~= 'dead') then
			player.last_state = 'dead'
			time_of_death = time()

			has_evaporated = false
			has_been_abandoned = false

			player.sprite:stop_animation()
			player.sprite.fill = 8
		end

		-- if (log_states) log'dead state'

		if time() - time_of_death > 0.8 and not(has_evaporated) then
			has_evaporated = true
			player.sprite.fill = nil
			player.sprite:animate(player, death_sprites, 18, false, 2)
		end

		if time() - time_of_death > 1.5 and not(has_been_abandoned) then
			rolo.loyal = false
		end

		if time() - time_of_death > 2.5 then
			load_scene'game_over'
		end

	end
}

local player_statuses = {
	default = function(player, states)

		-------
		-- init
		-------

		if (player.last_status ~= 'default') then
			player.last_status = 'default'
			player.invincible = false
		end

		----------------------
		-- run state functions
		----------------------

		-- if (log_statuses) log'normal status'

		player.sprite.fill = nil

		if player.state == player_states.dodging then
			player.sprite.outline = 13
		else
			player.sprite.outline = 0
		end

	end,
	hurt = function(player, states)

		-------
		-- init
		-------

		if player.last_status ~= 'hurt' then
			player.last_status = 'hurt'
			player.invincible = true
			player.hurt_start = time()
		end

		----------------------
		-- run state functions
		----------------------

		-- if (log_statuses) log'hurt status'

		local flash_length = 0.16
		player.sprite.outline = (time() - player.hurt_start) % (flash_length * 2) > flash_length and 8 or 2
		player.sprite.fill = (time() - player.hurt_start) % (flash_length * 2) > flash_length and 14 or nil

		-- exit state after time has passed
		if time() - player.hurt_start > 2 then
			player.status = states.default
		end
	end,
	dead = function(player, states)

		if player.last_status ~= 'dead' then
			player.last_status = 'dead'
			player.sprite.outline = 0
		end

		-- if (log_statuses) log'dead status'
	end
}

function player_init(self)

	p_velocity = self.velocity
	p_flipped = self.flipped

	self.health:set(15)
	resize(self, tile * 2, tile * 2)
	self.sprite.outline = 0,
	self.sprite:set(1)
	translate(self, 0, -(tile * 2))
	self.collider:set(self, vec(tile * 0.25, tile * 0.25), tile * 1.5, tile * 1.75)

	self.state = self.default_state
	self.status = self.default_status

end

function player_move(player)
	if btn'0' then
	 p_velocity:accelerate(-player.accel, 0)
	elseif btn'1' then
	 p_velocity:accelerate(player.accel, 0)
	end
end

function player_detect_flip()

	-- flip direction if not blocking
	if btn'0' and player.blocking == false then
		p_flipped = true
	elseif btn'1' and player.blocking == false then
		p_flipped = false
	end

	-- animate sprite
	player.sprite.flipped = p_flipped
	player.flip_x = p_flipped and -1 or 1

end


function player_update(self)

	if (player.state ~= player_states.dead) player_detect_flip()

	-- reset actions on button release
	if (not(btn'4') and player.state ~= player_states.attacking) player.can_attack = true
	if (not(btn'5') and player.state ~= player_states.dodging and player.grounded) player.can_dodge = true
	if (not(btn'2') and player.state ~= player_states.jumping) player.can_jump = true

end


function player_stop(direction, newvec, player, other)

	local other_col = other.collider
	local other_col_pos = vec(other.x + other_col.offset.x, other.y + other_col.offset.y)

	-- set position to the edge of the collision, depending on the edge that is colliding
	if (direction == 'right') then
		newvec.x = other_col_pos.x - player.w
	elseif (direction == 'left') then
		newvec.x = other_col_pos.x + other_col.w - 1
		newvec.x = other_col_pos.x + other_col.w - 1
	end
	if (direction == 'bottom') then
		newvec.y = other_col_pos.y - player.h
	elseif (direction == 'top') then
		newvec.y = other_col_pos.y + other_col.h - 1
		newvec.y = other_col_pos.y + other_col.h - 1
	end

	return newvec
end

function player_collision(self, newvec, other)

	-- get direction of collision, reverse if other object initiated
	local direction = collision_direction(self, other)

	-- potentially take damage
	if other.damage and other.alive ~= false and not(self.invincible) and (not(other.is_attack) or (other.is_hostile and other.armed)) then

		-- stop movement
		newvec = player_stop(direction, newvec, self, other)
		if (other.is_attack) other.armed = false

		-- determine if we were vulnerable to damage
		if
			(direction ~= 'left' and direction ~= 'right')
			or (p_flipped == false and direction == 'right' and self.blocking == false)
			or (p_flipped and direction == 'right')
			or (p_flipped and direction == 'left' and self.blocking == false)
			or (p_flipped == false and direction == 'left')
		then

			-- apply damage
			self.health:damage(other.damage)
			self.invincible = true
			self.stunned = true

			-- change state
			self.status = player_statuses.hurt

			-- blowback: throw in direction opposite instigator or self
			local flip = direction == 'left'
			local flip_x = (flip == false) and 1 or -1

			-- blowback: set new velocity and position
			self.thrown = true
			self.velocity:set(-self.dodge_forward * flip_x, self.jump / self.dodge_damp)

			-- return new coords
			newvec = vec(
				newvec.x + -self.dodge_forward * flip_x,
				newvec.y + self.jump / self.dodge_damp
			)

		end

	elseif not(other.damage) then
		-- if running into a normal collider, stop
		newvec = player_stop(direction, newvec, self, other)
	end

	-- return new coordinates
	return newvec

end

function game_over()
	trigger_state'dead'
	player.status = player_statuses.dead
end

-- make entity
player = {

	tag = 'player',

	-- compos
	'health',
	'velocity',
	'gravity',
	'sprite',
	'collider',

	-- flags
	grounded = true,
	alive = true,
	blocking = false,
	attacking = false,
	invincible = false,
	flipped = false,

	-- states
	last_state = '',
	can_attack = false,
	can_jump = false,
	can_dodge = false,

	-- constants
	jump = -8,
	dodge_damp = 3,
	dodge_forward = 5,
	dodge_length = 0.25,
	default_accel = 1.75,

	-- properties
	accel = 0,

	-- animations
	idle_fps = 0.03,
	idle_sprites = split'1, 33',
	idle_frame = 1,
	attack_length = 0.3,
	attack_sprites = split'35, 37, 39',
	block_sprites = split'33, 1, 3',
	running_sprites = split'66, 96, 64, 96, 66, 98, 68, 98',

	-- methods
	init = player_init,
	die = game_over,
	early_update = player_update,
	collision = player_collision,
	state_list = player_states,
	status_list = player_statuses,
	default_state = player_states.grounded,
	default_status = player_statuses.default
}

-- rolo
rolo = {

	tag = 'rolo',

    'sprite',

	fire_time = -1,
	cooldown = 0.25,
	can_fire = true,
	loyal = true,

    delay_x = 6,
    delay_y = 20,
    offset_y = 2,
	blocking_y = 5,

    offset_from_player = function(self)

		local new_x, new_y

		-- follow player, or leave if unloyal
		if self.loyal then
    		new_x = p_flipped and player.x + player.w or player.x - self.w
			new_y = player.blocking and self.blocking_y + player.y or self.offset_y + player.y
		else
			new_x = cam.x - 16
			new_y = cam.y + 64
		end

        translate(
			self,
			(new_x + self.x * ( self.delay_x - 1 )) / self.delay_x,
        	(new_y + self.y * ( self.delay_y - 1 )) / self.delay_y
		)

    end,

	fire = function(self)
		-- fire when ready
		if (self.can_fire) then
			self.can_fire = false

			local new_bullet = copy(bullet)
			new_bullet.flipped = p_flipped and -1 or 1
			add_actor(new_bullet)

			self.fire_time = time()
			self.sprite:stop_animation()
			self.sprite.id = 28

			p_velocity.x += -player.flip_x

		end
	end,

	idle = function(self)
		self.fire_time = -1
        self.sprite:animate(self, split'10, 26, 11, 27, 12, 27, 11, 26', 15, true)
	end,

    init = function(self)
		self.loyal = true
        translate(self, player.x, player.y)
		self:idle()
    end,

    update = function(self)
		-- reset to animation
		if (self.fire_time > -1 and time() - self.fire_time > self.cooldown) self:idle()

		-- reset fire
		if (btn'4' == false and self.fire_time == -1) self.can_fire = true

		self:offset_from_player()
		self.sprite.flipped = self.x > player.x + (player.w / 2)
		self.sprite.flipped = not(self.loyal) and true or self.sprite.flipped

    end
}

-- =======================================================
-- enemies
-- =======================================================

local worm_states = {
	alive = function(worm, states)
		if worm.alive == false then
			worm:die()
		end
	end,
	dead = function(worm, states)

		-- start death animation
		if worm.has_died ~= true then
			worm.has_died = true
			worm.sprite:stop_animation()
			worm.sprite:animate(worm, death_sprites, 18)
		end

		-- remove when complete
		if not(worm.sprite.animating) then
			remove_actor(worm)
		end
	end
}

local worm = {

	tag = 'worm',

	-- compos
	'sprite',
	'velocity',
	'patrol',
	'collider',
	'health',
	'gravity',

	damage = 1,

	init = function(self)

		-- set size and position
		self.collider:set(self)

		-- set health
		self.health:set(3)

		-- set patrol
		local target = vec(self.x, self.y)
		target.x -= tile * 6
		self.patrol:set(vec(self.x, self.y), target, 100, 1)

		-- set animations
		self.sprite:animate(self, { 16, 32, 48 }, 4, true)
	end,

	die = function(self)
		trigger_state('dead', self, worm_states)
	end,

	collision = function(self, newvec, other)

        -- turn around if facing object
        local direction = collision_direction(self.collider, other.collider)
        if (direction == 'right' and self.patrol.returning) or (direction == 'left' and not(self.patrol.returning)) then

            -- collide from player shield or all other objects
            if other.tag ~= 'player' or (
                other.blocking and (
                    not(p_flipped) and not(self.patrol.returning)
                    or
                    p_flipped and self.patrol.returning
                )
            ) then
                self.patrol:flip(self)
                newvec = vec(self.x, self.y)
            end
        end

        -- attacked
        if other.is_attack then
            hurt(self, other)
            if (self.health.total > 0) newvec = throw(self, newvec, other.damage * 2)
        end

        return newvec
	end,

	state_list = worm_states,
	default_state = worm_states.alive
}

local fireball = {

	tag = 'fireball',

	-- compos
	'collider',
	'velocity',
	'sprite',
	'age',

	damage = 2,
	is_attack = true,
	is_hostile = true,

	init = function(self)
		local flip_x = self.flipped and -1 or 1
		self.velocity:set(3 * flip_x, 0)
		self.sprite:animate(self, bullet_sprites, 20, true)
		self.armed = true
		self.age:set(1)
	end,

	collision = function(self, newvec, other)
		if other.tag ~= 'flower' then
			self.armed = false
			remove_actor(self)
		end
		return newvec
	end

}

local flower_states = {
	idling = function(flower, states)

		if flower.last_state ~= 'idling' then
			flower.last_state = 'idling'
		end

		if abs((player.x + player.w) - flower.x) < 40 or abs(player.x - (flower.x + flower.w)) < 40 then
			trigger_state('aggro', flower, states)
		end
	end,
	aggro = function(flower, states)

		if flower.last_state ~= 'aggro' then
			flower.last_state = 'aggro'
			flower.sprite:animate(flower, {76, 77}, 5, false)
			flower.attack_start = time()
			flower.should_fire = true
		end

		if flower.should_fire and time() - flower.attack_start > 0.2 then
			flower.should_fire = false
			spawn(13, flower.x, flower.y, true);
		end

		if not(flower.sprite.animating) then
			flower.sprite:animate(flower, {74, 75}, 5, true)
		end

		if flower.attack_start and time() - flower.attack_start > 1.5 then
			trigger_state('idling', flower, states)
		end

	end,
	dead = function(flower, states)

		-- start death animation
		if flower.has_died ~= true then
			flower.has_died = true
			flower.sprite:stop_animation()
			flower.sprite.w = tile
			flower.sprite.h = tile
			flower.sprite:animate(flower, death_sprites, 18)
		end

		-- remove when complete
		if not(flower.sprite.animating) then
			remove_actor(flower)
		end
	end
}

local flower = {

	tag = 'flower',

	-- compos
	'sprite',
	'collider',
	'health',

	damage = 2,

	init = function(self)
		resize(self, 8, 16)
		self.collider:set(self)
		self.health:set(4)
		self.sprite:animate(self, {74, 75}, 5, true)
	end,

	die = function(self)
		trigger_state('dead', self, flower_states)
	end,

	static_collision = function(self, other)
		if other.is_attack and not(other.is_hostile) then
			hurt(self, other)
		end
	end,

	state_list = flower_states,
	default_state = flower_states.idling
}


local knight_states = {
	idling = function(knight, states)

		if abs((player.x + player.w) - knight.x) < 32 or abs(player.x - (knight.x + knight.w)) < 32 then
			trigger_state('aggro', knight, states)
		end

		if knight.last_state ~= 'idling' then
			knight.last_state = 'idling'
			knight.sprite.id = 100
		end

		if knight.grounded then
			knight.velocity.x = 0
		end

	end,

	aggro = function(knight, states)

		if knight.last_state ~= 'aggro' then
			knight.last_state = 'aggro'
		end

		knight.sprite.flipped = player.x > knight.x
		local flip_x = knight.sprite.flipped and 1 or -1
		if (knight.grounded) knight.velocity.x = flip_x * 1

		if abs((player.x + player.w) - knight.x) < 12 or abs(player.x - (knight.x + knight.w)) < 12 then
			trigger_state('attacking', knight, states)
		end

	end,

	attacking = function(knight, states)

		if knight.last_state ~= 'attacking' then
			knight.last_state = 'attacking'
			knight.sprite.id = 70
			knight.velocity.x = 0
			knight.attack_time = time()
		end

		if time() - knight.attack_time > 0.4 then
			local flip_x = knight.sprite.flipped and 1 or -1
			if (knight.grounded) knight.velocity.x = flip_x * 3
		end

		if time() - knight.attack_time > 1 then
			knight.velocity.x = 0
			trigger_state('idling', knight, states)
		end

	end,

	dead = function(knight, states)

		if knight.last_state ~= 'dead' then
			knight.last_state = 'dead'
			knight.velocity:set(0, 0)
			knight.sprite:stop_animation()
			knight.sprite:animate(knight, death_sprites, 18, false, 2)
		end

		-- remove when complete
		if not(knight.sprite.animating) then
			remove_actor(knight)
		end

	end
}

local knight = {

	tag = 'knight',

	-- compos
	'sprite',
	'velocity',
	'collider',
	'health',
	'gravity',

	damage = 2,

	die = function(self)
		trigger_state('dead', self, knight_states)
	end,

	init = function(self)

		resize(self, 16, 16)
		self.collider:set(self)
		self.sprite:set(100)
		self.health:set(5)

	end,

	collision = function(self, newvec, other)

		if other.is_attack and not(other.is_hostile) then

			hurt(self, other)
			if (other.damage > 1 and self.health.total > 0) newvec = throw(self, newvec, 2)

			if (self.state == knight_states.idling) trigger_state('aggro', self, knight_states)

		end

		return newvec

	end,

	state_list = knight_states,
	default_state = knight_states.idling
}

-- =======================================================
-- creature management
-- =======================================================

local creatures = {
	mtile13 = fireball,
	mtile74 = flower,
	mtile16 = worm,
	mtile100 = knight
}

local block = {
	tag = 'block',
	'sprite',
	init = function(self, parent)
		self.sprite.id = self.sprite_id
		self.sprite.outline = self.outline
		if self.collider then
			self.collider:set(self);
		end
	end
}

function spawn(t, x, y, flipped)

	local c

	-- decoartion sprites are on page 4
	if t >= 192 then

		-- spawn a generic block
		c = copy(block)
		c.sprite_id = t
		c.background = fget(t, 2)
		c.outline = fget(t, 1) and 0 or -1

		-- collidable ground blocks have tag 7
		if fget(t, 7) then
			c.is_ground = true
			add(c, 'collider')
		end

	-- spawn a creature from a map tile
	elseif creatures['mtile'..t] then
		c = copy(creatures['mtile'..t])
	end

	-- move actor to spawn position and init
	if c then
		c.x = x
		c.y = y
		if (c.sprite) c.sprite.flipped = flipped
		add_actor(c)
	end

end

-- =======================================================
-- camera
-- =======================================================

cam_center = function(delay_x, delay_y)
	if player.x then

		-- move offset based on player direction
		local offset_x = p_flipped and -cam.offset_x or cam.offset_x

		-- center camera on plater
		if delay_x and delay_y then
			cam.x = max(cam.min_x, offset_x + (player.x - 56 + cam.x * (delay_x - 1)) / delay_x)
			cam.y = cam.offset_y
		end

		camera(cam.x, cam.y)

		-- todo: see if this is necessary
		-- cam.min_x = max(cam.min_x, cam.x - win_w)
	end
end

cam = {

	tag = 'camera',

	-- compos
	x = 0,
	y = 0,
	min_x = -win_w,

	-- unique
	delay_x = 7,
	delay_y = 10,
	started = false,
	offset_x = 3,
	offset_y = -104,

	early_update = function(self)

		if not(self.started) then
			cam_center(1, 1)
			self.started = true
		else
			cam_center(self.delay_x, self.delay_y)
		end

		win_l, win_r, win_t, win_b = self.x, self.x + win_w, self.y, self.y + win_h

	end
}


-- =======================================================
-- foreground
-- =======================================================

for i = 1, 30 do
	local lamp = {

		-- compos
		'sprite',

		init = function(self)
			translate(self, i * (tile * 10), tile)
			self.original_position = vec(self.x, self.y)
			self.sprite.outline = 6

			self.sprites = {8, 7, 9, 25}
			self.sprite:animate(self, self.sprites, 5, true)
		end,

		update = function(self)
			self.x = self.original_position.x + ((self.original_position.x - cam.x) / 5)
		end,

		draw = function(self)
			rect(self.x + 2, self.y + self.h + 1, self.x + self.w - 3, win_h, 6)
			rectfill(self.x + 3, self.y + self.h, self.x + self.w - 4, win_h, 2)
		end
	}

	add(game_actors, lamp)
end


-- =======================================================
-- scenes
-- =======================================================


local title_tuck = {
	'sprite',

	init = function(self)
		resize(self, 64, 64)
		translate(self, 40, 32)
		self.sprite:animate(self, { 1, 33 }, 0.75, true, 4)
	end,

	update = function(self)
	end,
}

local title_rolo = {
	'sprite',

	init = function(self)
		resize(self, 32, 32)
		translate(self, 10, 32)
		self.sprite:animate(self, {10, 26, 11, 27, 12, 27, 11, 26}, 15, true, 4)
	end,

	update = function(self)
	end,
}

local title_text = {
	draw = function(self)
		outline_print('tuck and rolo', 4, 4, 7, 5)
		outline_print('demo!', 104, 4, 7, 8)
		outline_print('@waltcodes', 84, 116, 1)
		outline_print('hit \142 to start', 4, 116, 8, 7)
	end
}

local title_actors = { title_tuck, title_rolo, title_text }

function map_init()
	local map_start = 100
	for x = 0, 128 do
		for y = 0, 16 do

			-- get map tile, break into next row if over map width
			local t = mget(x % 128, flr(x / 128) * 16 + y)
			local mtile = 'mtile'..t;

			-- spawn actors from map tiles
			spawn(t, map_start + x * tile, y * tile - win_h)

		end
	end
end

local scenes = {
	title = {
		init = function(self)
			actors = title_actors
			compos_init()
		end,
		update = function(self)
			if btn(4) then
				load_scene'game'
			end

			cam:early_update()

			compos_update()
		end,
		draw = function(self)
			cls()
			compos_draw()
		end
	},
	game = {
		init = function(self)

			-- initialize actors
			actors = copy(game_actors)
			add(actors, player)
			add(actors, rolo)

			-- init actors
			compos_init()

			-- make actors from map
			map_init()

		end,
		update = function(self)

			cam:early_update()

			-- component update
			compos_update()

		end,
		draw = function(self)

			-- clear screen
			if clear then
				cls()
				draw_background()
			end

			for actor in all(actors) do
				-- draw fixed to window then reset cam
				if actor.fixed_draw then
					camera()
					actor:fixed_draw()
					cam_center()
				end
			end

			-- component draw
			compos_draw()

		end
	},
	game_over = {
		init = function(self)
			translate(cam, 0, 0)
			self.end_time = time()
		end,
		update = function(self)
			if btn'4' then
				load_scene'game'
			end
			if time() - self.end_time > 10 then
				load_scene'title'
			end
		end,
		draw = function(self)

			-- clear screen
			cls()
			draw_background(true)
			outline_print('game over', 46, 100, 7, 2)
			outline_print('\142 to restart', 40, 108, 7, 2)

		end
	},
}

function load_scene(scene)

	-- reset actors and camera
	actors = {}
	camera()

	-- init scene
	active_scene = scenes[scene]
	if (active_scene and active_scene.init) active_scene:init()
	if (active_scene and active_scene.update) active_scene:update()

end

-- =======================================================
-- lifecycle management
-- =======================================================


function _init()

	load_scene'game'

end

function _update()

	if (active_scene) active_scene:update()

end

function _draw()

	if (active_scene) active_scene:draw()

end
__gfx__
00000000bbbb566666666bbbbbbbbbbbbbbbbbbbbb55666666bbbbbbbbbb8bbbbbb8bbbbbbabb8bbbb8bbb2bbbbbbbbbbbbb776bbbbbbbbbbbbbbbccccbbbbbb
00000000bbb56777777776bbbbbb566666666bbbbb567777777bbbbbbab898bbbb898bbbbbbb898bb88bbb22bbbbbbbbbbe87cdbbbbbbbbbbbbbccff76ccbbbb
00700700bbb67117777711bbbbb56777777776bbb6777117770bbbbbbb89a9bbb89998bbbb89a98bbe8bbb22bbbb776b2e888899bb7abbbbbbb7f7fff76fcbbb
00077000bbb671c777771cbbbbb67117777711bbb67771c777cbbbbbb897a98bb89aa98bb8977a98be8b7762e8887cd2be882b49b4aabbbbbbff7fff7ffffcbb
00077000bbb56777777776bbbbb671c777771cbbb5577777777bbbbb89a7a89889a7aa98b897aaa9bbe87cdb2e888899be88bb22bb99bbbbb7f777777ff7ffcb
00700700bbbb567777776bbbbbb56777777776bbbb556b67777bbbbb89aaaa9889aaaa98b89aaa982be88899b2e88b49bb88bb22bbbbbbbbb7777f7ff7777ffb
00000000bbbbbb070707bbbbbbbb567777776bbbbbbbb00707bbbbbbb896698bb896698bbb86698bb8888b49bb89bbbbbb88bb22bbbbbbbbfff7f77ff7777ffc
00000000bbbb76500000bba7bb6700070707aa77bbb7660000bba7bbbb5445bbbb5445bbbb5445bbb9bbbbbbbbbbbbbbbbb8bb2bbbbbbbbbf7f777ffffffff6c
bbeeebbbbb67b772866b5bafb57bb7200bbbaaf7bb7b76bbbaabafbbbbbbbbbbbbbbbbbbb6bb8b9bbbbbbbbbbbbbbbbbb8bbb2bbbbbbbbbbfff77777ffff776c
bf7f9ebbb57bbb5771bbb6a967bbb5771bbba99fbb7bbb7aab95a9bbbbbbbbbbbbbbbbbbbbb898bb8bbbbbb2bbbb776b88bbb22bbbb99bbbfff777777ffff7fc
b707febb67bbbb7116bbbba9676bb7116bbbaa97bbb7b7aa99bba9bbbbbbbbbbbbbbbbbbbb89a98be88bbb22bb887cd2e8bbb22bbb97a9bbbfff77f77fff77fb
bf7f42bb676bbb5761bbb7a9675ab5761bbbaa9abbbb77a9bbbbb9bbbbbbbbbbbbbbbbbbb897aa98b88b77622b888899e8b7762bb4a7a9bbbffff7fffff776fb
beee2bbb675abb7766bbb6a9b64aa7766bbbaa9abbbbb7766bb6b9bbbbbbbbbbbbbbbbbbb897aa98be887cdbbe882b49be87cdbbbb4aa9bbbbdffffffff76fbb
beebbbebb64aa66bb56bb5aabbb9aabb56bb9aaabbbbb67b56b5abbbbbbbbbbbbbbbbbbbb89aa98b2be88899be88bb22be888999bbb99bbbbbbdfffffffffbbb
b2eeee2bbbb9aabbb56bbb9abbb69abbb56b4aaabbbbb7bb56bb9abbbbbbbbbbbbbbbbbbbb8668bbb8888b49b88bbbb28888b4bbbbbbbbbbbbbbddfff66fbbbb
bb2ee2bbbbbb9a7bbb566bb9bb566bbbbb56649bbbbb677bb566b9bbbbbbbbbbbbbbbbbbbb5445bbbb9bbbbbbbbbbbbb9bbbbb4bbbbbbbbbbbbbbbddddbbbbbb
bbeeebbbbbbbb566666666bbbb55666666bbbbbbbbbb55666666bbbbbbbb55666666bbbbbbbbbbbbbdbbbbdbd6dbbd6dd6fd6f6dbbbbbbbbbbbbbb2222bbbbbb
bf7f9ebbbbbb56777777776bb5567777777bbbabbbb5567777777bbbbbb5567777777bbbbbbbbbbbd6dbbd6d6ffddff6bd6d66d6bbb799bbbbbbb200002bbbbb
b707febbbbbb67117777711bb6677117770babbbbbb6677007770babbbb6677007770bbbbbbbbbbb6f6dd6f666f66f6ddbd6fd6db77a7a9bbbbb200220dccbbb
bf7f42bbbbbb671c777771cbb66771c777cabaabbbb66770c777cbbbbbb66770c777cbbbbbbbbbbb6ff66ffdd66ff66dbbdf6ddb9997aa9bbbb200200d555cbb
beee2bbbbbbb56777777776bb5567777777baa9bbbb5567777777bb9bbb5567777777babbbbbbbbbd66ff66dbd6666dbbd6d6dbbb22aaa9bbbddd000d55d55cb
beebbebbbbbbb567777776bbbb556667777aa9bbbbbb55666777bbabbbbb55666777b9bbbbbbbbbbbd6666dbd66ff66ddbdbdbbdbbb299bbb255550d55d5d55b
b2eee2ebbbbbbbb070707bbbbbbbb06700aa9bbbbbbbbbb06707abbbbbbbbb006707bbabbbbbbbbbd6ffff6dd6ffff6dbdbbdbbbbbbbbbbb200ddd55555555dc
bb2e2b2bbbbb766500000a7bbbbbb6000076bbbbbbbbbb6500004baabbbbbb6500000bb9bbbbbbbbd6f66f6dbd6ff6dbbbbbbbbbbbbbbbbb20d5502555555d0d
beeebbbbbbb7b772866b5afbbbbb76286764bbbbbbbbb76285224aaabbbbb762852249bbbddbbddbbd6bb6dbd6fbbf6dbbdbdbdbbbbbbbbb677bbbbbaabbbbbb
f7f9ebbbbb57bb5771bb6a9bbbbb67667624bbbbbbbbb756625aaaa9bbbbb75772529bb9d66dd66d6ff66ff66fd666f6bd6d6dd6bbb99bbbb667799977aabbbb
707febbbb67bbb7116bbba9bbbbbb6772224bbbbbbbbb7777749999bbbbbb77112524bab6ff66ff66f6ff6fdd6666d6dbbd6fdbdbb97a9bbbbb667799977aabb
f7f42bbbb676bb5761bb7a9bbbbbb5762224bbbbbbbbbb5762224bbbbbbbbb67722249ba6ff6d6fdd666666dbddffd6dbbdfdbbbbba7a94bbbbbb667799977bb
bee2bbbbb675ab7766bb6a9bbbbbb7762224bbbbbbbbbb7762224bbbbbbbbb7767aaaabad66f666dbd6ff6dbbd6ff6dbbbbd6dbbbb4aa9bbbbbbbbb6677999bb
beebbbbbbb64aa6bb56b5aabbbbbbb6b624bbbbbbbbbbb6bb624bbbbbbbbb6bb5b4aaaa9bdd6ff6dd6f66f6dd6d66dbdbbbbdbbdbbb99bbbbbbbbbbbb667bbbb
b2eeeeeebbbb9aabb56bb9abbbbbb6b5b4bbbbbbbbbbb6bb5b4bbbbbbbbb6bbbb5b9aaaabbd6f6dbd666666dbdbdd6dbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bb2ee22bbbbb69abbb566b9bbbbbb67755bbbbbbbbbbb677555bbbbbbbbb677bb555999abbbd6dbbbd6dd6dbbbbbbdbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbbb55666666bbbbbbbbbbbbbbbbbbbbbbbb55666666bbbbbbb44bbbb44bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb99aabbbbbbbbbbbbbbbbbb677bbbabbbbbbbbb
bbbb5567777777bbbbbbbb55666666bbbbbb5567777777bbbbbb4bbbbbb4bbbbbbbbbbbbbbbbbbbbbb99aabbb99999abbbb99aabbb99aabbb6677bbaaaabbbbb
bbbb6677117770bbbbbbb5567777777bbbbb6677117770bbbbbb44222244bbbbbbbbbbbbbbbbbbbbb99999abb99999abbb99999ab99999abbbb6677b99aabbbb
bbbb66771c777cbbbbbbb6677117770bbbbb66771c777cbbbbbbb8222e2bbbbbbbbbbbbbbbbbbbbbb99999abb272299bbb78999ab78999abbbbbb6677999aaab
bbbb5567777777bbbbbbb66771c777cbbbbb5567777777bbbbbbb882882bbbbbbbbbbbbbbbbbbbbbb272299bbb22299bbb778899bbb8899bbbbbbbb66779997a
bbbbb55666777bbbbbbbb5567777777bbbbbb55666777bbbbbbbbb22221bbbbbbbbbbbbbbbbbbbbbbb22299bb77729bbb4999899bbb8899bbbbbbbbbb6677a7a
bbbbb000067070f7bbbbbb556667777bbbbbb000067070bbbbbbbb2221bbbbbbbbbbbbbbbbbbbbbbb77729bb999993bbbb499993bb87893bbbbbbbbbaaaaa77a
bb7777b7200004a7bbbb77000067070bbbbbbbb7200004bbbbbbb1000022bbbbbbbbbbbbbbbbbbbb99999344b94bb344bbb4993bbb799b34bbbbbbbbbbbaa7aa
b77bbbb576bf499abbbb7bb72800004bbbbbbb75762524bbbeeeeb11222b2bbbbbbbbbbbbbbbbbbbb94bb354bbbbb354bbbbbb3bb994bb54bbbbbbbbbbbbbbbb
baabbbb751baa9aabbb77bb576bb6f9bbbbbb7b6512524bb88888e11221b2bbbbbbbbbbbbbbbbbbbbbbb53bbbbbb53bbbbbbb334b4bbb33bbbbbbbbbbbbbbbbb
b9abbbb566baa9aabbb77bb751bb6a9bbbbbb777aaaaaabbbb88bb1111b2bbbbbbbbbbbbbbbbbbbbbbb43bbbbbb43bbbbbbb5354bbbb53bbbbbb677aaabbbbbb
bbbbbbb776b9a9aabbbb7ab566bb7a9bbbbbbb77999aabbbbb444444442bbbbbbbbbbbbbbbbbbbbbbb443bbbbb443bbbb4533bbbbb453bbbbbbbb6677aaaabbb
bbbbbbbb7774aaaabbbb9aaa66bb6a9bbbbbbb6bbb555bbbbb88bbb1b1bbbbbbbbbbbbbbbbbbbbbbbbb43bbbbbb43bbb443bbbbbb443bbbbbbbbbbb66799a7bb
bbbb5555bbb749abbbbbb9aaab5bbaabbbb776bbbbbb5bbb8888ee1bb2bbbbbbbbbbbbbbbbbbbbbbbbbb3bbbbbbb3bbbb433bbbbbb43bbbbbbbbbbbba67797bb
bbbbbbbbbbb677bbbbbbbbbaa5bbb9abbbbbbbbbbbbb555bb8888b1bbb2bbbbbbbbbbbbbbbbbbbbbbbbb35bbbbbb35bbbbb335bbbbb335bbbbbbbbaaa69997bb
bbbbbbbbbbbbbbbbbbbbbbb77755bb9bbbbbbbbbbbbbbbbbbbbb111b222bbbbbbbbbbbbbbbbbbbbbbb53335bbb53335bbb53335bbb53335bbbbbbbbbaaaaaabb
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb44bbbb44bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbbb55666666bbbbbbbb55666666bbbbbbb4bbbbbb4bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbb5567777777bbbbbb5567777777bbbbbb44222244bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbb6677117770bbbbbb6677117770bbbbbbb8e28e2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbb66771c777cbbbbbb66771c777cbbbbbbb882882bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbb5567777777bbbbbb5567777777bbbbbbbb22221bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbbb55666777bbbbbbbb55666777bbbbbbbbb2221bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbb6000067070fbbbbbb0000670704bbb8eb1000022bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbb76bb720000f4bbbbbb7b720b0024bbb8e1b12222b2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bb77bbb576bbfa4bbbbb67b566b2524bbb2e1b1222bbb2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbaabbb751bbaa9bbbbb67b751b2524bb7281b1222eee22bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bb9aabb566bbaa9bbbbb67b566b2524b6628bbb11e88e42bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbb9abb766bbaa9bbbbbb77aaab2224bb628bbb1b8884eebbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbbbbbb777b9aabbbbbbb79aaaa24bbbb28bb11288488ebbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbbb555bb7bb9abbbbb766bb9aaabbbbb88bbb1b24888ebbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
bbbbb5bbbb677bbbbbbb7bbbbb555bbbbb8bb11222b888bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbb9bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb228bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bb22522b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
822b4b28000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
222b4b22000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
21bb4bb2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbb4bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbb7bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb77b6b0111515d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb7766b011111150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bb776977001111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bb779777010111150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bb77777b001111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bb6777bb000101110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb366bb000010110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bb336bbbe888e8880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb36bbb222222220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb36bb3111500400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb3333b001100900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3bb3333b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b3633bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b3333bbb000011150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb36bbb000000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb36bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb33bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b223349b111500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b244444b001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b99997ab000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9999997a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9999997a000011150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b999999b000000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0001000100010080808000000000000002000000000000000080000000000000020100010001000100000000000000000200000000000000000000000000000001000100010000000001000000000000000000000000000000000000000000000100010000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000020400000000000000000000000000000280000000000000000000000000000002800000000000000000000000000000
__map__
00000000000000000000000000000000000000000000000000d1d1d1d1d1d1d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000d10000000000000000d100000000d1d1d1d1d1d1d1d1d1d1d1000000d100d100d1d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000d1d1d1d1d1d100000000000000000000d1d100000000000000d1d1d1d1d1d1d1d1000000d1d1d100d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000d000000000d1d1d1d1d1d1d1d1d1d100d1d1d1d100000000d1d10000d1000000d100d1d1d10000d1d100d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000d000000000e000000000d1d1d1d1d1d1d1d1d1d100000000d1d1d1d1d1d1d1d1d1d10000000000d10000d100d1d100d1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000d000000000e000000000e000000000d100d1000000d1d1d1d1d1d1000000d1d100000000d1d1d1d1d1d100d1d1d100d1d100d1d1d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000e000000000e000000000e000000000d10000d100d1d1d100d1d1d100d1d100d1d100d100d1d1d1d1d1d1d1d1d1d1d10000d10000d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000f000000000f000000000f000000000d10000d1d1d1d100d1d1d1d1d1d1d10000d1d1d1d1d1d1d1d1d1000000d1d100d100d1d100d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e100d10000d1d1d1d1d1d1d1d1d1d1d1d1d1d100d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d10000d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d100d1d100d1d10000000000d100d1d1d1d100d1d1d10000000000d1d10000d1d1d1d1d100d1d100d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1000000d1d1d100000000d10000d1d1d1d10000d1d100d100d1d1d1d1d1d100d1d1d1d1d1d1d1d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1000000d1d1000000d1d1000000d1d100000000d1d1d1d100d1d10000d1d100d1d100d1d1d1d1d1d100d100d10000d10000d100000000d1d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1000000d1d1000000d1d1000000d1d10000d10000d1000000d1d1d1d100d1d10000d10000000000d1000000d100000000d10000d100d1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1000000d1d1000000d1d1c0c0c0d1d1000000d1d1d1d1d1d1d1d1d1d100000000000000d100000000d10000d1d10000d1d1d1d1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1000000d1d1c0c0c0d1d1e1e1e1e1e10000d1d10000000000000000d1d1d100d100d10000d1d1d1d1d100d1d1d100d1d1d1d100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1d1c0c0c0d1d1e1e1e1e1e1f1f1f1f1f1f10000d1d1d1d1000000d1d1d1d100d100d1000000d10000d100000000d1d1d1d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000d1d1d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000e5e500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
00010000223501f3501c3501a3501d3501f35021350243502b3500030000300003000030000300043000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

