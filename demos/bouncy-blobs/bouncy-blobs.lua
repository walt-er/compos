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
