pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
package={loaded={},_c={}}
package._c["core/core"]=function()
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

actors, visible_actors, to_remove, update_pool, stages, update_id = {}, {}, {}, {}, split'state_update, early_update, update, late_update, fixed_update, background_draw, early_draw, draw, late_draw', 1

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
end
package._c["core/debugging"]=function()
-- =======================================================
-- debugging helpers (remove for prod)
-- =======================================================

logs, permalogs, show_colliders, show_stats, log_states = {}, {}, false, false, false

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
    unshift(logs, message)
end

function plog(message)
    unshift(permalogs, message)
end
end
package._c["core/drawing"]=function()
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
	local outline = outline or 0
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
    local outline = outline or 0
    rectfill(x, y-1, x2, y2+1, outline)
    rectfill(x-1, y, x2+1, y2, outline)
    rectfill(x, y, x2, y2, fill)
end

function outline_circ(x, y, r, fill, outline)
    local outline = outline or 0
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

function outline_spr(id, x, y, w, h, outline, fill, flip_x, flip_y, zoom, color_map)

    -- don't outline
	if outline == -1 then
        set_transparent_colors()
        zspr(id, x, y, w, h, flip_x, flip_y, zoom)
	else

        -- change all colors to outline color
        local outline = outline or 0
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

        -- reset palette
        set_transparent_colors()

        if fill then

            -- change all colors to fill color
            for i=0, 15 do
                if (i ~= transparent) pal(i, fill)
            end

        elseif color_map then

            -- map colors to other colors
            pal(color_map[1], color_map[2])

        end

        -- draw!
        zspr(id, x, y, w, h, flip_x, flip_y, zoom)

        -- reset palette
        set_transparent_colors()

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
end
package._c["components/velocity"]=function()
-- //////////////
-- velocity
-- //////////////

compos.velocity = {
    x = 0,
    y = 0,
    max_x = 999,
    max_y = 999,
    decay = vec(1, 1),
    set = function(self, x, y, decay, cap)
        self.x, self.y = x, y
        if (decay) self.decay = decay
		if (cap) self:cap(cap.x, cap.y)
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
        self.actualvec = self.newvec

        --decay
        self.x *= self.decay.x
        self.y *= self.decay.y

    end,
    fixed_update = function(self, parent)

        -- apply velocity after all collisions
        if (self.actualvec) translate(parent, self.actualvec.x, self.actualvec.y)

    end
}
end
package._c["components/gravity"]=function()
-- //////////////
-- gravity
-- //////////////

compos.gravity = {
    force = 1,
    set = function(self, force)
        self.force = force
    end,
    early_update = function(self, parent)
        parent.velocity.y += self.force
    end,
	fixed_update = function(self, parent)
		parent.grounded = not(parent.should_unground)
		parent.should_unground = false
	end
}

function trigger_grounding(parent, other, newvec)

    local direction = collision_direction(parent, other)
    if direction == 'bottom' then
        parent.should_unground = false
        parent.velocity.y = min(0, parent.velocity.y)
        newvec.y = other.y + other.collider.offset.y - parent.h
    end

    return newvec

end
end
package._c["components/collider"]=function()
-- //////////////
-- collisions
-- //////////////

function collision_direction(col1, col2)

    local overlapping_y = not(col1.grounded) or col1.y + col1.h < col2.y

    local direction,
		left_overlap,
		right_overlap,
		bottom_overlap,
		top_overlap
		=
		'',
		col1.x >= col2.x + col2.w and overlapping_y,
		col1.x + col1.w <= col2.x and overlapping_y,
		col1.y + col1.h < col2.y,
		col1.y > col2.y + col2.h

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
function points_sqrdist(point1, point2)
    return (point1.x-point2.x)^2+(point1.y-point2.y)^2
end

function rect_center(rect)
	return vec(rect.x + (rect.w / 2), rect.y + (rect.h / 2));
end

function rect_sqrdist(rect1, rect2)
	return points_sqrdist(rect_center(rect1), rect_center(rect2))
end

function rect_overlap(rect1, rect2)
    local x = rect1.x + rect1.w >= rect2.x and rect1.x <= rect2.x + rect2.w
    local y = rect1.y + rect1.h >= rect2.y and rect1.y <= rect2.y + rect2.h
    return x and y
end

-- todo: make this real! right now it just checks against corners
function circle_overlapping_rect(obj1, obj2)

    -- determine which is circle and which is rect
    local r, circle, rectangle = obj1.r or obj2.r, obj1.r and obj1 or obj2, obj1.r and obj2 or obj1

    -- get rect bounds
    local rect_l, rect_r, rect_t, rect_b = rectangle.x, rectangle.x + rectangle.w, rectangle.y, rectangle.y + rectangle.h

    -- check for overlap
    local overlap_tl = r*r > sqrdist(circle, vec(rect_l, rect_t))
    local overlap_tr = r*r > sqrdist(circle, vec(rect_r, rect_t))
    local overlap_bl = r*r > sqrdist(circle, vec(rect_l, rect_b))
    local overlap_br = r*r > sqrdist(circle, vec(rect_r, rect_b))

    return overlap_tl or overlap_tr or overlap_bl or overlap_br

end

-- based in part on work by bridgs
-- https://github.com/bridgs/trans-gal-jam
function overlapping(obj1, obj2)
    local r1, r2 = obj1.r, obj2.r

    -- two circles overlapping
    if r1 and r2 then
        return sqrdist(obj1, obj2) < (r1+r2)^2

    -- one circle, one rect overlapping
    elseif r1 or r2 then
        return circle_overlapping_rect(obj1, obj2)

    -- two rectangles overlapping
    else
        return rect_overlap(obj1, obj2)
    end

    return false
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
        if overlapping(parent_col, other_col) then

            if parent.velocity then

                -- run gravity collision with objects below
                -- run collision calculations on parent object if needed
                if parent.gravity and not(parent.thrown) and other.is_ground then
                    parent.velocity.actualvec = trigger_grounding(parent, other, parent.velocity.newvec)
                end
                if parent.collision then
                    parent.velocity.actualvec = parent:collision(parent.velocity.newvec, other)
                end

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
            parent.should_unground, parent.thrown = true, false
        end

        -- loop over all colliders if parent has collider
        -- the ground never starts a collision
        if parent.collision or parent.static_collision then

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
end
package._c["components/sprite"]=function()
-- //////////////
-- sprite (requires core/drawing)
-- //////////////

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
        self.animating, self.loop, self.sheet, self.frame, self.fps, self.zoom, self.t = true, loop, spritesheet, 0.1, fps, zoom or 1, time()
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

	init = function(self, parent)

		self.flipped = parent.flipped

		if parent.background then
			self.background_draw = self.draw_sprite
		elseif parent.early then
			self.early_draw = self.draw_sprite
		elseif parent.foreground then
			self.late_draw = self.draw_sprite
		else
			self.draw = self.draw_sprite
		end

	end,

    update = function(self, parent)

		local sheet = self.sheet

        -- loop over spritesheet if it exists
        if sheet and #sheet > 0 then

            -- iterate over frames
            local frame = (time() - self.t) * self.fps
            frame = self.loop and frame % #sheet or min(#sheet, frame)

            -- set new frame
            self.id = sheet[max(1, ceil(frame))] + 0

            -- stop animation (if not looping) at end of sheet
            if (not(self.loop) and frame >= #sheet) self:stop_animation()

        end

        -- flash
        if self.flash_count > -1 and self.flashes < self.flash_count then
            if not(self.flashing) then

                if (self.old_fill == -1) then
                    self.old_fill = self.fill or nil
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
		local parent_x = parent.adjusted_x or parent.x
        local parent_y = parent.adjusted_y or parent.y
		local spr_x = parent_x + (parent.w / 2) - (self.w / 2)
		local spr_y = parent_y + (parent.h / 2) - (self.h / 2)

        -- draw the sprite!
        outline_spr(
            self.id,
            spr_x,
            spr_y,
            (self.w / tile) / self.zoom,
            (self.h / tile) / self.zoom,
            self.outline,
            self.fill,
            self.flipped,
            self.flip_y,
            self.zoom,
            self.color_map
        )
    end
}
end
function require(p)
local l=package.loaded
if (l[p]==nil) l[p]=package._c[p]()
if (l[p]==nil) l[p]=true
return l[p]
end
require('core/core')
require('core/debugging')
require('core/drawing')

require('components/velocity')
require('components/gravity')
require('components/collider')
require('components/sprite')

-- make actors as objects
-- copy compos to enable their functions
-- set compo values inside of init
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
            self.sprite:animate(self, split'0,2,0,4', 1, true)
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
            local direction = collision_direction(self, other)
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

    show_stats = true

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
__label__
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

