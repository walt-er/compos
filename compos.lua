-- =======================================================
-- generic globals
-- =======================================================

win_w, win_h, win_l, win_r, win_t, win_b, tile, cam, player, player_states = 128, 128, 0, 128, 0, 128, 8, {}, {}, {}

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

logs, permalogs, show_colliders, log_states, log_statuses = {}, {}, false, false, false

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

local transparent = 11
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
    line(x, y, x2, y, outline)
    line(x2, y, x2, y2, outline)
    line(x2, y2, x, y2, outline)
    line(x, y2, x, y, outline)
    rectfill(x + 1, y + 1, x2 - 1, y2 - 1, fill)
end

function outline_circ(x, y, r, fill, outline)
    outline = outline or 0
    circfill(x,y,r,fill)
    circ(x,y,r,outline)
end

function zspr(n, dx, dy, w, h, flip_x, flip_y, dz)
	if not(dz) or dz==1 then
		spr(n,dx,dy,w,h,flip_x,flip_y)
    elseif n >= 0 then
        sx, sy, sw, sh = shl(band(n, 0x0f), 3), shr(band(n, 0xf0), 1), shl(w, 3), shl(h, 3)
		dw, dh = sw * dz, sh * dz
        sspr(sx,sy,sw,sh,dx,dy,dw,dh,flip_x,flip_y)
    end
end

function offset_spr(offset_x, offset_y, id, x, y, w, h, flip_x, flip_y, zoom)
    zspr(id, x + offset_x, y + offset_y, w, h, flip_x, flip_y, zoom)
end

function outline_spr(id, x, y, w, h, outline, fill, flip_x, flip_y, zoom)

	-- change all colors to outline
    outline = outline or 0
    for i=1, 15 do
        if (i ~= transparent) pal(i, outline)
    end

    -- draw outline sprites
    for i = -1, 1 do
        for j = -1, 1 do
            if not(abs(i) == abs(j)) then
                offset_spr(i, j, id, x, y, w, h, flip_x, flip_y, zoom)
            end
        end
    end

    -- fill sprite or draw full color sprite
    if fill then
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
-- =======================================================
-- components (compos!)
-- =======================================================
-- =======================================================

function resize(thing, w, h)
	thing.w = w
	thing.h = h
end

--

function translate(thing, x, y)
	thing.x = x
	thing.y = y
end

--

health = {
    total = -999,
    max = 0,
    set = function(self, new_health)
        self.max = max(0, new_health)
        self.total = max(0, new_health)
    end,
    damage = function(self, damage)
        self.total = self.total - damage
        self.damage_time = time()
    end,
    update = function(self, parent)

        -- store life as flag on parent
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

            -- draw
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
	local throwvec = vec(player.flip_x * distance, -distance)
	actor.velocity:set(throwvec.x, throwvec.y)
	actor.thrown = true
	return vec(newvec.x + throwvec.x, newvec.y + throwvec.y)
end

--

velocity = {
    x = 0,
    y = 0,
    max_x = 999,
    max_y = 999,
    decay = vec(1, 1),
    newvec = vec(0, 0),
    set = function(self, x, y, decay)
        self.x = x
        self.y = y
        if (decay) self.decay = decay
    end,
    accelerate = function(self, x_acceleration, y_acceleration)
        self.x += x_acceleration
        self.y += y_acceleration
    end,
    cap = function(self, x, y)
        self.max_x = x
        self.max_y = y
    end,
    update = function(self, parent)

        self.x = mid(self.x, -self.max_x, self.max_x)
        self.y = mid(self.y, -self.max_y, self.max_y)

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

-- TODO: refactor
function collision_direction(col1, col2, flipped)
    local direction = ''

    local left_overlap = col1.x > col2.x + col2.w - 1
    local right_overlap = col1.x + col1.w - 1 <= col2.x
    local bottom_overlap = col1.y + col1.h - 1 <= col2.y
    local top_overlap = col1.y >= col2.y + col2.h - 1

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
		local new_col1 = obj(col1.x + 1, col1.y + 1, col1.w - 2, col1.h - 2)
		local new_col2 = obj(col2.x + 1, col2.y + 1, col2.w - 2, col2.h - 2)
        return collision_direction(new_col1, new_col2, flipped)
    else
        return direction
    end
end

collider_id = 0
colliders = { fixed = {} }
collider = {
    physical = true,
    offset = vec(0, 0),
    set = function(self, parent, offset, w, h, fixed)

        -- set size and offset from parent
        self.offset = offset or vec(0, 0)
        self.w = w or parent.w
        self.h = h or parent.h

        -- set position
        self.x = parent.x + self.offset.x
        self.y = parent.y + self.offset.y

        parent.id = collider_id
        collider_id += 1

        -- add to array of colliders
		self.chunk = fixed and 'fixed' or ''..flr(self.x / win_w)
		if (not(colliders[self.chunk])) colliders[self.chunk] = {}
        colliders[self.chunk][''..collider_id] = { self, parent }

    end,
	move = function(self, newvec)
        self.x = newvec.x + self.offset.x
        self.y = newvec.y + self.offset.y
	end,
	check_collision = function(self, parent, other)

		-- only continue if this isn't the parent collider
		if other and other.id ~= parent.id then
			local parent_col, other_col = parent.collider, other.collider

			local overlap_x = (parent_col.x + parent_col.w >= other_col.x)
				and (parent_col.x <= other_col.x + other_col.w)

			local overlap_y = (parent_col.y + parent_col.h >= other_col.y)
				and (parent_col.y <= other_col.y + other_col.h)

			-- only take action if colliders overlap
			if overlap_x and overlap_y then
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
			local chunk = flr(self.x / win_w)

			-- permanent colliders
			for id, v in pairs(colliders['fixed']) do
				self:check_collision(parent, v[2])
			end

			-- nearby colliders
			for i = chunk - 1, chunk + 1 do
				if colliders[''..i] then
					for id, v in pairs(colliders[''..i]) do
						self:check_collision(parent, v[2])
					end
				end
			end
		end
    end,

    fixed_update = function(self, parent)

		self.x = parent.x + self.offset.x
		self.y = parent.y + self.offset.y

    end,

    draw = function(self, parent)
        if (show_colliders) rect(self.x, self.y, self.x + self.w, self.y + self.h, 11)
    end
}

--

gravity = {
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

sprite = {
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

age = {
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

patrol = {
    start = vec(0, 0),
    target = vec(0, 0),
    tick = 0,
    step = 0,
    duration = 0,
    fixed = false,
    direction = 'going',

    set = function(self, start, target, duration, step, fixed)
        self.start, self.target, self.duration, self.step, self.fixed, self.direction = start, target, duration, step, fixed, 'going'
    end,

    flip = function(self, parent)

        -- turn around
        self.direction = self.direction == 'going' and 'coming' or 'going'
        parent.sprite.flipped = self.direction == 'coming'

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
            if parent.grounded and self.direction == 'coming' then
                parent.velocity.x = distance_chunk
            elseif parent.grounded and self.direction == 'going' then
                parent.velocity.x = -distance_chunk
            end

            -- set sprite direction
            parent.sprite.flipped = self.direction == 'coming'

            -- reverse when reaching end
            if (self.tick >= self.duration) then
                self.tick = 0
                self.direction = self.direction == 'going' and 'coming' or 'going'
            end

        end
    end
}

-- =======================================================
-- actor helpers
-- =======================================================

local actors, to_remove, update_pool, stages = {}, {}, {}, split'early_update, update, late_update, fixed_update, early_draw, draw'

function reset_update_pool()
	update_pool = {}
	for stage in all(stages) do
		update_pool[stage] = {
			array = {},
			lookup = {}
		}
	end
end

function make_physical(thing)
	thing.x = thing.x or 0
	thing.y = thing.y or 0
	thing.w = thing.w or tile
	thing.h = thing.h or tile
end

local update_id = 1

function register(actor, parent)
    parent = parent or actor

	for stage in all(stages) do
		if actor[stage] then
			actor.update_id = update_id
			local registrant = {actor, parent}
            add(update_pool[stage].array, registrant)
            update_pool[stage].lookup[''..update_id] = registrant
            update_id += 1
        end
	end
end

function unregister(actor)
	for stage in all(stages) do
		if actor[stage] then
			local stage_pool = update_pool[stage]
			local registrant = stage_pool.lookup[''..actor.update_id]
            del(stage_pool.array, registrant)
            del(stage_pool.lookup, registrant)
        end
	end
end

-- TODO: find memory leak in registration
function init_actor(actor)
	if (actor.physical) make_physical(actor)
    register(actor)

	for k, compo in pairs(actor) do
		if type(compo) == 'table' then
			if (compo.physical) make_physical(actor[k])
			if (compo.init) actor[k]:init()
			register(compo, actor)
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
    del(actors, actor)
    unregister(actor)

	for k, compo in pairs(actor) do
		if type(compo) == 'table' then
			unregister(compo)
		end
	end

    if (actor.collider) del(colliders, colliders[actor.collider.chunk][''..actor.id])
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
	logs, new_permalogs = {}, {}
	for i = 1, 15 do
		log(permalogs[i])
		add(new_permalogs, permalogs[i])
	end
	permalogs = new_permalogs

	-- loop over all actors to determine if in frame
	for actor in all(actors) do

		-- only loop over (nearly) visible actors
		if cam.x and actor.x and not(actor.fixed) then
			actor.in_frame = actor.x + actor.w >= cam.x - win_w * 0.1 and actor.x <= cam.x + win_w * 1.1 and actor.y + actor.h >= cam.y - win_h * 0.1 and actor.y <= cam.y + win_h * 1.1
		end

		if actor.in_frame then

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

	-- debug logs
	for i = 1, #logs do
        camera()
		outline_print(logs[i], 5, 5 + ((i - 1) * tile), 7)
	end
end