


--  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.  .----------------.
-- | .--------------. || .--------------. || .--------------. || .--------------. || .--------------. || .--------------. |
-- | |     ______   | || |     ____     | || | ____    ____ | || |   ______     | || |     ____     | || |    _______   | |
-- | |   .' ___  |  | || |   .'    `.   | || ||_   \  /   _|| || |  |_   __ \   | || |   .'    `.   | || |   /  ___  |  | |
-- | |  / .'   \_|  | || |  /  .--.  \  | || |  |   \/   |  | || |    | |__) |  | || |  /  .--.  \  | || |  |  (__ \_|  | |
-- | |  | |         | || |  | |    | |  | || |  | |\  /| |  | || |    |  ___/   | || |  | |    | |  | || |   '.___`-.   | |
-- | |  \ `.___.'\  | || |  \  `--'  /  | || | _| |_\/_| |_ | || |   _| |_      | || |  \  `--'  /  | || |  |`\____) |  | |
-- | |   `._____.'  | || |   `.____.'   | || ||_____||_____|| || |  |_____|     | || |   `.____.'   | || |  |_______.'  | |
-- | |              | || |              | || |              | || |              | || |              | || |              | |
-- | '--------------' || '--------------' || '--------------' || '--------------' || '--------------' || '--------------' |
--  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'  '----------------'
--
--  ~/picotool-master/p8tool build compos.p8 --lua=compos.lua

-- =======================================================
-- generic globals
-- =======================================================

window_w, window_h, tile, cam = 128, 128, 8, {};

-- =======================================================
-- helper functions
-- =======================================================

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

function clamp(num, minimum, maximum)
    return max(minimum, min(maximum, num));
end

function reverse(table)
    for i=1, flr(#table / 2) do
        table[i], table[#table - i + 1] = table[#table - i + 1], table[i]
    end
end

function unshift(array, value)
    reverse(array);
    add(array, value);
    reverse(array);
end

function vector(x,y)
    return {
        x = x,
        y = y
    }
end

-- =======================================================
-- debugging helpers
-- =======================================================

logs, permalogs, show_colliders, log_states, log_statuses = {}, {}, false, false, false;

function log(message)
    add(logs, message);
end

function plog(message)
    unshift(permalogs, message);
end

-- =======================================================
-- state helpers
-- =======================================================

function trigger_state(state, actor, states)
    actor.state = states[state];
    if (actor.state) actor.state(actor, states);
    return;
end

-- =======================================================
-- drawing helpers
-- =======================================================

function outline_print(s, x, y, c1, c2)
    for i = -1, 1 do
        for j = -1, 1 do
            if not(i == j) then
                print(s,x+i,y+j,c1)
            end
        end
    end
    print(s, x, y, c2)
end

function zspr(n, dx, dy, w, h, flip_x, flip_y, dz)
    if n >= 0 then

        dz = dz ~= nil and dz or 1;

        sx = shl(band(n, 0x0f), 3);
        sy = shr(band(n, 0xf0), 1);
        sw = shl(w, 3);
        sh = shl(h, 3);
        dw = sw * dz;
        dh = sh * dz;

        sspr(sx,sy,sw,sh,dx,dy,dw,dh,flip_x,flip_y)

    end
end

function offset_spr(offset_x, offset_y, id, x, y, w, h, flip_x, flip_y, zoom)
    if (zoom) then
        zspr(id, x + offset_x, y + offset_y, w, h, flip_x, flip_y, zoom);
    else
        spr(id, x + offset_x, y + offset_y, w, h, flip_x, flip_y);
    end
end

function set_transparent_colors()

    -- set transparency color
    palt(11, true);
    palt(0, false);

end

function outline_spr(id, x, y, w, h, outline, fill, flip_x, flip_y, zoom)

    -- default outline to black
    outline = outline == nil and 0 or outline;

    -- change all colors to outline color
    for i=1, 15 do
        if (i ~= 11) pal(i, outline);
    end

    -- draw outline sprites
    for i = -1, 1 do
        for j = -1, 1 do
            if not(abs(i) == abs(j)) then
                offset_spr( i, j, id, x, y, w, h, flip_x, flip_y, zoom)
            end
        end
    end

    -- fill sprite (optional)
    if fill then
        for i=0, 15 do
            if (i ~= 11) pal(i, fill);
        end

        -- draw filled sprite
        if zoom then
            zspr(id, x, y, w, h, flip_x, flip_y, zoom);
        else
            spr(id, x, y, w, h, flip_x, flip_y);
        end


        -- reset colors
        pal();
        set_transparent_colors();

    else

        -- reset colors
        pal();
        set_transparent_colors();

        -- draw filled sprite
        if zoom then
            zspr(id, x, y, w, h, flip_x, flip_y, zoom);
        else
            spr(id, x, y, w, h, flip_x, flip_y);
        end

    end

end

function outline_rect(x, y, x2, y2, fill, outline);

    outline = outline == nil and 0 or outline;

    line(x, y - 1, x2, y - 1, outline);
    line(x2 + 1, y, x2 + 1, y2, outline);
    line(x2, y2 + 1, x, y2 + 1, outline);
    line(x - 1, y2, x - 1, y, outline);
    rectfill(x, y, x2, y2, fill);

end;

-- =======================================================
-- actor helpers
-- =======================================================

actors, colliders, to_remove = {}, {}, {};

function add_actor(actor)
    add(actors, actor);
    if (actor.init) actor:init();
end

function remove_actor(actor)
    del(actors, actor);
    if (actor.collider) then
        colliders[''..actor.id] = nil;
        del(colliders, nil);
    end
end


-- =======================================================
-- =======================================================
-- components (compos!)
-- =======================================================
-- =======================================================

size = {
    x = 0,
    y = 0,
    set = function(self, x, y)
        self.x = x;
        self.y = y;
    end
}

width = function(thing)
    return thing.size.x;
end

height = function(thing)
    return thing.size.y;
end

--

position = {
    x = 0,
    y = 0,
    set = function(self, x, y)
        self.x = x;
        self.y = y;
    end,
    translate = function(self, x, y)
        self.x += x;
        self.y += y;
    end
}

pos_x = function(thing)
    return thing.position.x;
end

pos_y = function(thing)
    return thing.position.y;
end

-- camera must have position
cam.position = copy(position);
cam.position:set(0,0);

--

health = {
    total = 0,
    max = 0,
    set = function(self, new_health)
        self.max = max(0, new_health);
        self.total = max(0, new_health);
    end,
    damage = function(self, damage)
        self.total = self.total - damage;
        self.damage_time = time()
    end,
    update = function(self, parent)

        -- store life as flag on parent
        parent.alive = self.total > 0;

        -- show health bar when damaged
        self.show_health = self.damage_time and time() - self.damage_time < 2;

    end,
    draw = function(self, parent)
        if (self.show_health and parent.alive) then

            -- calculate position of health bar to draw
            local start_x = pos_x(parent) - 2;
            local start_y = pos_y(parent) - 8;
            local end_x = pos_x(parent) + width(parent) + 2;
            local end_y = pos_y(parent) - 6;

            -- get end x for fill representing remaining health
            local fill_end_x = start_x + flr((end_x - start_x) * (self.total / self.max));

            -- draw
            outline_rect(start_x, start_y, end_x, end_y, 6, 1);
            line(start_x, end_y, end_x, end_y, 13);
            outline_rect(start_x, start_y, fill_end_x, end_y, 8);
            line(start_x, start_y, fill_end_x, start_y, 14);

        end
    end
}

function hurt(other, attack)
    if
        not(other.tag == 'player')
        and not(other.is_attack)
        and not(other.is_ground)
        and other.health
        and other.health.total > 0
    then

        -- if valid target, hurt other and remove attack object
        other.health:damage(attack.damage);
        if (other.sprite) other.sprite:flash();
        add(to_remove, attack);

    end
end

--

velocity = {
    decay = vector(1, 1),
    x = 0,
    y = 0,
    new_coords = vector(0, 0),
    max_x = 999,
    max_y = 999,
    set = function(self, x, y, decay)
        self.x = x;
        self.y = y;
        if (decay) self.decay = decay;
    end,
    accelerate = function(self, x_acceleration, y_acceleration)
        self.x += x_acceleration;
        self.y += y_acceleration;
    end,
    cap = function(self, x, y)
        self.max_x = x;
        self.max_y = y;
    end,
    update = function(self, parent)

        -- clamp velocity
        self.x = clamp(self.x, -self.max_x, self.max_x);
        self.y = clamp(self.y, -self.max_y, self.max_y);

        -- get new set of coordinates using current velocity (don't apply yet)
        self.new_coords = vector(pos_x(parent) + self.x, pos_y(parent) + self.y);

        -- move collider if need be
        if parent.collider then
            parent.collider.position = vector(
                self.new_coords.x + parent.collider.offset.x,
                self.new_coords.y + parent.collider.offset.y
            );
        end

        --decay
        self.x *= self.decay.x;
        self.y *= self.decay.y;

    end,
    fixed_update = function(self, parent)

        -- apply velocity after all collisions
        parent.position = vector(
            self.new_coords.x,
            self.new_coords.y
        );

    end
}

--

function collision_direction(obj1, obj2, flipped)
    local direction = '';

    local left_overlap = pos_x(obj1) >= pos_x(obj2) + width(obj2) - 1;
    local right_overlap = pos_x(obj1) + width(obj1) - 1 <= pos_x(obj2);
    local bottom_overlap = pos_y(obj1) + height(obj1) - 1 <= pos_y(obj2);
    local top_overlap = pos_y(obj1) >= pos_y(obj2) + height(obj2) - 1;

    if right_overlap or (flipped and left_overlap) then
        direction = 'right';
    elseif left_overlap or (flipped and right_overlap) then
        direction = 'left';
    elseif top_overlap or (flipped and bottom_overlap) then
        direction = 'top';
    elseif bottom_overlap or (flipped and top_overlap) then
        direction = 'bottom';
    end

    -- if no direction, retry with smaller colliders
    if direction == '' and width(obj1) > 2 and height(obj1) > 2 and width(obj2) > 2 and height(obj2) > 2 then
        new_obj1 = {
            position = vector(pos_x(obj1) + 1, pos_y(obj1) + 1),
            size = vector(width(obj1) - 2, height(obj1) - 2)
        }
        new_obj2 = {
            position = vector(pos_x(obj2) + 1, pos_y(obj2) + 1),
            size = vector(width(obj2) - 2, height(obj2) - 2)
        }
        return collision_direction(new_obj1, new_obj2, flipped);
    else
        return direction;
    end
end

collider = {
    position = vector(0, 0),
    offset = vector(0, 0),
    size = vector(0, 0),
    set = function(self, parent, offset, size)

        -- set offset from parent size
        if (offset ~= nil) then
            self.offset = offset;
        else
            self.offset = vector(0, 0);
        end

        -- set size
        if (size ~= nil) then
            self.size = size;
        else
            self.size = parent.size;
        end

        -- set position
        self.position = vector(
            pos_x(parent) + self.offset.x,
            pos_y(parent) + self.offset.y
        );

        -- add to array of colliders
        colliders[''..parent.id] = { self, parent };

    end,
    late_update = function(self, parent)

        -- reset gravity, only set grounded to true if colliding with ground
        if parent.gravity then
            parent.grounded = false;
        end

        -- loop over all colliders if parent has collider
        -- the ground never starts a collision
        if not(parent.is_ground) then
            for id, v in pairs(colliders) do
                local other = v[2];

                -- only continue if this isn't the parent collider
                if other and other.id ~= parent.id then

                    local parent_col, other_col = parent.collider, other.collider;

                    local overlap_x = (parent_col.position.x + parent_col.size.x >= other_col.position.x)
                        and (parent_col.position.x <= other_col.position.x + other_col.size.x);

                    local overlap_y = (parent_col.position.y + parent_col.size.y >= other_col.position.y)
                        and (parent_col.position.y <= other_col.position.y + other_col.size.y);

                    -- only take action if colliders overlap
                    if overlap_x and overlap_y then

                        if (parent.velocity) then

                            -- run gravity collision with objects below
                            if (parent.gravity and other.is_ground) parent.velocity.new_coords = parent.gravity:trigger_grounding(parent, other, parent.velocity.new_coords);

                            -- run collision calculations on parent object if needed
                            if (parent.collision) parent.velocity.new_coords = parent:collision(parent.velocity.new_coords, other);

                        elseif parent.collision then

                            parent:collision(other);

                        end
                    end
                end
            end
        end
    end,

    fixed_update = function(self, parent)

        -- move collider to new position
        local parent_coords = parent.velocity and parent.velocity.new_coords or parent.position;
        self.position = vector(parent_coords.x + self.offset.x, parent_coords.y + self.offset.y);

    end,

    draw = function(self, parent)

        if (show_colliders) then
            rect(self.position.x, self.position.y, self.position.x + self.size.x - 1, self.position.y + self.size.y - 1, 11);
            rect(self.position.x, self.position.y, self.position.x + self.size.x - 1, self.position.y + self.size.y - 1, 11);
            rect(self.position.x, self.position.y, self.position.x + self.size.x - 1, self.position.y + self.size.y - 1, 11);
        end

    end
}

--

gravity = {
    force = 1.1,
    set = function(self, force)
        self.force = force;
    end,
    early_update = function(self, parent)

        parent.velocity.y += self.force;

    end,
    trigger_grounding = function(self, parent, other, new_coords)

        local direction = collision_direction(parent, other);

        if direction == 'bottom' or direction == '' then
            parent.grounded = true;
            new_coords.y = other.collider.position.y - parent.size.y
        end

        return new_coords;
    end
}

--

input = {
    player = 0,
    btn = function(self, nice_button)
        local button;

        -- map nice strings to input ints
        if     nice_button == 'left' then button = 0;
        elseif nice_button == 'right' then button = 1;
        elseif nice_button == 'up' then button = 2;
        elseif nice_button == 'down' then button = 3;
        elseif nice_button == 'o' then button = 4;
        elseif nice_button == 'x' then button = 5;
        end

        return btn(button, self.player);
    end,
    set_player = function(self, player)
        self.player = player;
    end
}

--

sprite = {
    id = 0,
    fps = 0,
    sheet = {},
    loop = false,
    zoom = nil,
    animating = false,
    frame = 0.1,
    t = 0,
    reversed = false,
    flash_count = -1,
    old_fill = -1,
    old_outline = -1,

    set = function(self, id, size)
        self.id = id;
        self.size = size;
    end,

    animate = function(self, parent, spritesheet, fps, loop, zoom)

        self.animating = true;

        -- default to no loop
        self.loop = loop;

        -- register a spritesheet and speed for animation
        self.sheet = spritesheet;
        self.frame = 0.1;
        self.fps = fps;
        self.zoom = zoom;
        self.t = time();

    end,

    stop_animation = function(self)

        -- remove spritesheet
        self.sheet = {};
        self.animating = false;

    end,

    flash = function(self, color, outline, count, frame_length)
        self.flashes = 0;
        self.flashing = false;
        self.flash_color = color or 8;
        self.flash_outline = outline or 2;
        self.flash_frame_length = frame_length or 3;
        self.flash_count = count or self.flash_frame_length;
    end,

    reset_flash = function(self)
        self.fill = self.old_fill;
        self.outline = self.old_outline;
        self.flashing = false;
        self.old_fill = -1;
        self.old_outline = -1;
        self.flash_count = -1;
    end,

    update = function(self, parent)

        -- loop over spritesheet if it exists
        if (#self.sheet ~= 0) then

            -- iterate over frames
            local frame = (time() - self.t) * self.fps;
            frame = (self.loop == true) and frame % #self.sheet or min(#self.sheet, frame);

            -- set new frame
            self.id = self.sheet[max(1, ceil(frame))];

            -- stop animation (if not looping) at end of sheet
            if (not(self.loop) and frame >= #self.sheet) self:stop_animation();

        end

        -- flash
        if self.flash_count > -1 and self.flashes < self.flash_count then
            if not(self.flashing) then

                if (self.old_fill == -1) then
                    self.old_fill = self.fill ~= nil and self.fill + 0 or nil;
                    self.old_outline = self.outline ~= nil and self.outline + 0 or nil;
                end

                self.fill = self.flash_color
                self.outline = self.flash_outline;
                self.flashes += 1;
                if (self.flashes % self.flash_frame_length == 0) self.flashing = true;
            else
                self:reset_flash();
            end
        elseif self.flash_count ~= -1 then
            self:reset_flash();
        end

    end,

    draw = function(self, parent)

        if not(self.size) then
             self.size = parent.size;
        end

        -- render selected sprite at position
        outline_spr(self.id, parent.position.x, parent.position.y, self.size.x / tile, self.size.y / tile, self.outline, self.fill, self.reversed, false, self.zoom)

    end
}

--

age = {
    set = function(self, death)
        self.birth = time();
        self.death = death;
    end,
    update = function(self, parent)
        if self.birth and time() - self.birth > self.death then
            remove_actor(parent);
        end
    end,
}

--

patrol = {
    start = vector(0, 0),
    target = vector(0, 0),
    tick = 0,
    step = 0,
    duration = 0,
    fixed = false,
    direction = 'going',

    set = function(self, start, target, duration, step, fixed)
        self.start = start;
        self.target = target;
        self.duration = duration;
        self.step = step;
        self.fixed = fixed;
        self.direction = 'going';
    end,

    flip = function(self, parent)

        -- turn around
        self.direction = self.direction == 'going' and 'coming' or 'going';
        parent.sprite.reversed = self.direction == 'coming';

        -- remain in patrol area if fixed, otherwaise restart tick
        self.tick = self.fixed and self.duration - self.tick or 0;

    end,

    early_update = function(self, parent)
        if not(parent.alive) then

            -- stop patrol on death
            parent.velocity.x = 0;

        else

            -- up counter and calculate progress
            self.tick += self.step;
            local progress = self.tick / self.duration;

            -- get distance chunk
            local time_chunk = self.duration / self.step;
            local distance_chunk = abs(self.target.x - self.start.x) / time_chunk;

            -- calculate velocity
            if (self.direction == 'coming') then
                parent.velocity.x = distance_chunk;
            elseif (self.direction == 'going') then
                parent.velocity.x = -distance_chunk;
            end

            -- set sprite direction
            parent.sprite.reversed = self.direction == 'coming';

            -- reverse when reaching end
            if (self.tick >= self.duration) then
                self.tick = 0;
                self.direction = self.direction == 'going' and 'coming' or 'going';
            end

        end
    end
}


-- =======================================================
-- lifecycle management
-- =======================================================

-- to go in _init()
function compos_init()

	set_transparent_colors();

	-- init for all actors
	for actor in all(actors) do
		if actor.init then
			actor:init();
		end
	end

end

-- to go in _update()
function compos_update()

	-- reset logs
	logs = {};
	for i = 1, 10 do
		log(permalogs[i])
	end

	-- loop over all actors and their props to early update
	for actor in all(actors) do

		-- default to 'in frame' for actors with no position
		actor.in_frame_x = true;
		actor.in_frame_y = true;

		-- only loop over (nearly) visible actors
		if (actor.position) then
			actor.in_frame_x = (actor.position.x >= (cam.position.x - window_w)) and (actor.position.x < (cam.position.x + (window_w * 2)));
			actor.in_frame_y = (actor.position.y >= (cam.position.y - window_h)) and (actor.position.y < (cam.position.y + (window_h * 2)));
		end

		if (actor.in_frame_x) and (actor.in_frame_y) then
			for k, v in pairs(actor) do
				if type(actor[k]) == 'table' and actor[k].early_update then
					actor[k]:early_update(actor)
				end
			end
		end

		-- create state machines if needed
		if (actor.state == nil and actor.default_state) actor.state = actor.default_state;
		if (actor.status == nil and actor.default_status) actor.status = actor.default_status;

		---------------------
		-- run state machines
		---------------------
		if (actor.state) actor.state(actor, actor.state_list);
		if (actor.status) actor.status(actor, actor.status_list);

		-- update parent actor
		if actor.early_update then
			actor:early_update();
		end
	end

	-- loop over all actors and their props to normal update
	for actor in all(actors) do

		if (actor.in_frame_x) and (actor.in_frame_y) then
			for k, v in pairs(actor) do
				if type(actor[k]) == 'table' and actor[k].update then
					actor[k]:update(actor)
				end
			end
		end

		-- update parent actor
		if actor.update then
			actor:update();
		end
	end

	-- loop over all actors and their props to late update
	for actor in all(actors) do

		if (actor.in_frame_x) and (actor.in_frame_y) then
			for k, v in pairs(actor) do
				if type(actor[k]) == 'table' and actor[k].late_update then
					actor[k]:late_update(actor)
				end
			end
		end

		-- update parent actor
		if actor.late_update then
			actor:late_update();
		end
	end

	-- loop over all actors and their props to fixed update
	for actor in all(actors) do

		if (actor.in_frame_x) and (actor.in_frame_y) then
			for k, v in pairs(actor) do
				if type(actor[k]) == 'table' and actor[k].fixed_update then
					actor[k]:fixed_update(actor)
				end
			end
		end

		-- update parent actor
		if actor.fixed_update then
			actor:fixed_update();
		end
	end

	-- remove objects
	for i = 1, #to_remove do
		remove_actor(to_remove[i]);
	end
	to_remove = {};

end

-- to go in _draw()
-- don't forget to run cls() first
function compos_draw()

	-- early draw for background pieces
	for actor in all(actors) do
		if actor.early_draw then
			actor:early_draw();
		end
	end

	for actor in all(actors) do
		-- draw all props
		for k, v in pairs(actor) do
			if type(actor[k]) == 'table' and actor[k].draw then
				actor[k]:draw(actor)
			end
		end

		-- draw parent actor
		if actor.draw then
			actor:draw();
		end
	end

	-- debug logs
	for i = 1, #logs do
		outline_print(logs[i], cam.position.x + 5, cam.position.y + 5 + ((i - 1) * tile), 0, 7)
	end
end
