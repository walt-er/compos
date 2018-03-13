pico-8 cartridge // http://www.pico-8.com
version 14
__lua__
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

-- del by index - keeps order
-- by ultrabrite
-- https://www.lexaloffle.com/bbs/?pid=35344
function idel(t,i)
    local n=#t
    if i>0 and i<=n then
        for j=i,n-1 do t[j]=t[j+1] end
        t[n]=nil
    end
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

logs, permalogs, show_colliders, show_stats, log_states, log_statuses = {}, {}, true, true, false, false

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
    actor.state = states[state]
    if (actor.state) actor.state(actor, states)
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

-- todo: find memory leak in registration
function init_actor(actor)
	make_physical(actor) -- add properties for x, y, w, and h
    register(actor)

	for k, compo_name in pairs(actor) do
        local compo = compos[compo_name]
		if compo then
            actor[compo_name] = copy(compo)
			if (compo.physical) make_physical(actor[compo_name])
			if (compo.init) actor[compo_name]:init(actor)
			register(actor[compo_name], actor)
		end
	end

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
function make_physical(thing)
	thing.x, thing.y, thing.w, thing.h = thing.x or 0, thing.y or 0, thing.w or tile, thing.h or tile
end

function resize(thing, w, h)
    if h then
        thing.w, thing.h = w, h
    else
        thing.r, thing.w, thing.h = w, w, w
    end
end

function translate(thing, x, y)
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

        -- move collider if need be
        if (parent.collider) parent.collider:move(self.newvec)

        --decay
        self.x *= self.decay.x
        self.y *= self.decay.y

    end,
    fixed_update = function(self, parent)

        -- apply velocity after all collisions
        translate(parent, self.newvec.x, self.newvec.y)

    end
}

-- todo: refactor
function collision_direction(col1, col2, flipped)
    local direction = ''

    local left_overlap, right_overlap, bottom_overlap, top_overlap = col1.x > col2.x + col2.w - 1, col1.x + col1.w - 1 <= col2.x, col1.y + col1.h - 1 <= col2.y, col1.y >= col2.y + col2.h - 1

    if right_overlap or (flipped and left_overlap) then
        direction = 'right'
    elseif left_overlap or (flipped and right_overlap) then
        direction = 'left'
    elseif top_overlap or (flipped and bottom_overlap) then
        direction = 'top'
    elseif bottom_overlap or (flipped and top_overlap) then
        direction = 'bottom'
    end

    -- if no direction, retry with smaller colliders
    if direction == '' and col1.w > 2 and col1.h > 2 and col2.w > 2 and col2.h > 2 then
		local new_col1, new_col2 = obj(col1.x + 1, col1.y + 1, col1.w - 2, col1.h - 2), obj(col2.x + 1, col2.y + 1, col2.w - 2, col2.h - 2)
        return collision_direction(new_col1, new_col2, flipped)
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

-- based in part on work by bridgs
-- https://github.com/bridgs/trans-gal-jam
function overlapping(obj1, obj2)
    local r1, r2 = obj1.r, obj2.r

    -- two circles overlapping
    if r1 and r2 then

        return sqrdist(obj1, obj2) < (r1+r2)^2

    -- one circle, one rect overlapping
    -- todo: make this real! right now it just checks against corners
    elseif r1 or r2 then

        local r = r1 or r2
        local circle = r1 and obj1 or obj2
        local rectangle = r1 and obj2 or obj1

        local rect_l, rect_r, rect_t, rect_b = rectangle.x, rectangle.x + rectangle.w, rectangle.y, rectangle.y + rectangle.h

        local overlap_tl = r*r > sqrdist(circle, vec(rect_l, rect_t))
        local overlap_tr = r*r > sqrdist(circle, vec(rect_r, rect_t))
        local overlap_bl = r*r > sqrdist(circle, vec(rect_l, rect_b))
        local overlap_br = r*r > sqrdist(circle, vec(rect_r, rect_b))

        return overlap_tl or overlap_tr or overlap_bl or overlap_br

    -- two rectangles overlapping
    else

        local x = obj1.x + obj1.w >= obj2.x and obj1.x <= obj2.x + obj2.w
        local y = obj1.y + obj1.h >= obj2.y and obj1.y <= obj2.y + obj2.h
        return x and y

    end

    return false
end

collider_id = 0
compos.collider = {
    physical = true,
    offset = vec(0, 0),
    set = function(self, parent, offset, fixed, w, h)

        -- set size and offset from parent
        self.offset = offset or vec(0, 0)
        self.x = parent.x + self.offset.x
        self.y = parent.y + self.offset.y

        -- set dimensions
        if parent.r then
            local r = w or parent.r
            self.r, self.w, self.h = r, r, r
        else
            self.w = w or parent.w
            self.h = h or parent.h
        end

        -- add to array of colliders
        parent.id = parent.id or collider_id
        collider_id += 1

    end,
	move = function(self, newvec)
        self.x = newvec.x + self.offset.x
        self.y = newvec.y + self.offset.y
	end,
	check_collision = function(self, parent, other)

		-- only continue if this isn't the parent collider
		if other.collider and other.id ~= parent.id then

			-- only take action if colliders overlap
			if overlapping(parent.collider, other.collider) then
				if (parent.velocity) then

					-- run gravity collision with objects below
					if (parent.gravity and not(parent.thrown) and other.is_ground) parent.velocity.newvec = parent.gravity:trigger_grounding(parent, other, parent.velocity.newvec)

					-- run collision calculations on parent object if needed
					if (parent.collision) parent.velocity.newvec = parent:collision(parent.velocity.newvec, other)

				elseif parent.static_collision then

					parent:static_collision(other)

				end
			end
		end
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
				self:check_collision(parent, actor)
			end
		end
    end,

    fixed_update = function(self, parent)

		self.x = parent.x + self.offset.x
		self.y = parent.y + self.offset.y

    end,

    draw = function(self, parent)
        if show_colliders then
            if self.r then
                circ(self.x, self.y, self.r, 11)
            else
                rect(self.x, self.y, self.x + self.w, self.y + self.h, 11)
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
    end,
    trigger_grounding = function(self, parent, other, newvec)

        local direction = collision_direction(parent, other)
        if direction == 'bottom' then
            parent.grounded = true
			parent.velocity.y = min(0, parent.velocity.y)
            newvec.y = other.collider.y - parent.h
        end

        return newvec
    end
}

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
        -- todo: refactor
        if self.flash_count > -1 and self.flashes < self.flash_count then
            if not(self.flashing) then

                if (self.old_fill == -1) then
                    self.old_fill = self.fill ~= nil and self.fill + 0 or nil
                    self.old_outline = self.outline ~= nil and self.outline + 0 or nil
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

    draw = function(self, parent)

		self.w = self.w or parent.w
		self.h = self.h or parent.h
		self.zoom = self.zoom or 1

        -- render selected sprite at position
		local spr_x = parent.x + (parent.w / 2) - (self.w / 2)
		local spr_y = parent.y + (parent.h / 2) - (self.h / 2)
        outline_spr(self.id, spr_x, spr_y, (self.w / tile) / self.zoom, (self.h / tile) / self.zoom, self.outline, self.fill, self.flipped, self.flip_y, self.zoom)

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
-- demo!
-- =======================================================

-- make actors as objects
-- copy compos to enable their functions
-- set compo values insite of init
-- include init(), update(), and draw() if this actor should have its own methods
local blob = {
    'velocity',
    'gravity',
    'collider',

    tag = 'blob',

    init = function(self)

        -- move it to a random position
        translate(self, rnd'128', 64)

        -- make a circle or a rect
        if flr(rnd'6') > 3 then
            resize(self, flr(rnd'8'+4))
        else
            resize(self, flr(rnd'8'+4), flr(rnd'8'+4))
        end

        -- randomize the gravity on this object specifically
        self.gravity:set(max('0.025', rnd'0.05'))

        -- randomize inititial velocity and cap
        self.velocity:set(0,rnd'2'-1, vec(0.95, 1))
        self.velocity:cap(2,2)

        -- set collider to new size
        self.collider:set(self)

    end,
    update = function(self)

        local r = self.r or 0

        -- reverse velocity if beyond window bounds
        if self.y + self.h > win_h then
            translate(self, self.x, win_h - self.h)
            self.velocity.y = -4
        elseif self.y - r < win_t then
            translate(self, self.x, win_t + r)
            self.velocity.y = 0
        end
        if self.x - r < win_l then
            translate(self, win_l + r, self.y)
            self.velocity.x = rnd'2'+1
        elseif self.x + self.w > win_r then
            translate(self, win_r - self.w, self.y)
            self.velocity.x = -(rnd'2'+1)
        end

    end,
    draw = function(self)
        -- draw the shape during the draw function
        if self.r then
            outline_circ(self.x, self.y, self.r, self.color, self.outline)
        else
            outline_rect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, self.color, self.outline)
        end
    end
}

-- "split" is a handy method for reducing lengthy objects into 2-token function calls
local blob_colors = split'1, 2, 13, 6'

-- add these objects to the list of actors
-- local blob_count = 249
local blob_count = 250

for i = 1, blob_count do

    -- assign colors based on depth
    local color_index = ceil((i / blob_count) * (#blob_colors))
    blob.color = blob_colors[color_index]
    blob.outline = blob_colors[max(1, color_index - 1)]

    -- add blob to actors
    add(actors, copy(blob))

end

-- make a special blob with collision
local collider_blob = combine(
    copy(blob),
    {
        'sprite',

        tag = 'player',

        init = function(self)
            self.color = 7
            resize(self, 16, 16)
            translate(self, 56, 56)
            self.velocity:set(1, 0)
            self.gravity:set'0.1'
            self.outline = 0
            self.sprite:animate(self, split'0, 2, 0, 4', 1, true)
            self.collider:set(self)
        end,

        -- you can also register for special update stages
        -- options are early_upate, late_update, and fixed_update (or early_draw!)
        late_update = function(self)

            -- flip sprite based on direction
            self.sprite.flipped = self.velocity.x < 0

            -- controls!
            local push = 0.3
            if btn'0' then
                self.velocity:accelerate(-push, 0)
            elseif btn'1' then
                self.velocity:accelerate(push, 0)
            elseif btn'2' then
                self.velocity:accelerate(0, -push)
            elseif btn'3' then
                self.velocity:accelerate(0, push)
            end
        end,

        -- if an actor has a "collision" function, it will check for collisions with other colliders every frame
        -- all actors can have colliders at little cost, but too many "collision" functions add up!
        collision = function(self, newvec, other)

            -- this function takes too colliders and returns the direction of collision
            -- the direction returned (left, right, top, or bottom) is relative to the parent
            local direction = collision_direction(self.collider, other.collider)
            if (direction == '') direction = rnd'2' > 0 and 'left' or 'right'

            -- this could be done better :/
            -- it's a demo, gimme a break!
            local bump_force_x, bump_force_y, x_bump, y_bump = self.velocity.x, self.velocity.y, other.velocity.x, other.velocity.y
            local r = other.r or 0
            if direction == 'left' then
                x_bump = min(bump_force_x, 0) - 1
                other.velocity.newvec.x = newvec.x - other.w -- newvec is where the parent object will be at the ned of this frame
            elseif direction == 'right' then
                x_bump = max(bump_force_x, 0) + 1
                other.velocity.newvec.x = newvec.x + self.w + r
            elseif direction == 'top' then
                y_bump = min(bump_force_y) - 1
                other.velocity.newvec.y = newvec.y - other.h
            elseif direction == 'bottom' then
                y_bump = max(bump_force_y) + 1
                other.velocity.newvec.y = newvec.y + self.h + r
            end

            other.velocity:set(x_bump, y_bump)

            return newvec
        end
    }
);

-- add to compos actors
add(actors, collider_blob)

-- -- not all actors need compos!
local title_text = {
    update = function(self)
        self.y = 64 + sin(time()) * 8
    end,
    draw = function(self)
        local message = 'compos!'
        outline_print(message, 64 - #message * 2, self.y, 7, 8)
    end
}

-- pico8 lifecycle functions
-- call compos_* functions or add other scene logic
function _init()

    -- init runs on all objects currently within "actors"
    compos_init()

    -- you can add actors after compost_init with add_actor
    add_actor(title_text)

end

function _update()

    compos_update()

    -- debugging example; log out number of actors
    -- this could also go in any actors update function
    log('actors: '..#actors)

end

function _draw()

    -- compos doesn't clear screen, that's up to you!
    cls()
    compos_draw()

end

__gfx__
dddddddddddddddddddddddddddddddddddddddddddddddd00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222732227322d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122227722277222d122222772227722d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122227322273222d122222222d22222d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
12222222d222222d12222222ddd2222d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
1222222ddd22222d122222222222222d122222732227322d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222266d66222d122222222d22222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
12222226d622222d122222226662222d12222222ddd2222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222222222222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222226d62222d00000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222222222222d10000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222222222222d10000000000000000000000000000000000000000000000000000000000000000000000000000000
122222222222222d122222222222222d122222222222222d10000000000000000000000000000000000000000000000000000000000000000000000000000000
11111111111111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000
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

__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
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
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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

