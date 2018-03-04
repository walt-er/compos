# compos: reusable components for object-oriented PICO-8

compos: like "components", but with fewer characters!

compos are independent, reusable objects that can be added to your game's actors to give them certain behaviors. compos manage their own state, initialization, updating, and drawing. The only thing you might need to do is set some intitial values.

There's a fair amount of overhead for defining so many components right out of the gate. But hopefully the savings come down the line: it's easy to attach behaviors to actors independently, so defining large numbers of actors with similar behaviors is simple and doesn't require messy class inheritance. This system is build with procedural generation in mind -- it's easy to spawn complex actors on the fly, mixing and matching qualities without spending tokens.

The compos include:
* Position
* Size
* Velocity
* Gravity
* Collider
* Age
* Patrol

This library also includes a number of helper functions, including methods for drawing sprites and primitives with outlines, integrated logging, generating vectors, copying tables, tiling sprites, and more.

More importantly, the methods for adding and removing actors from the active list, used in conjunction with the compos update pool (where actors and compos register to run their updates), mean that once you've defined an init(), update() or draw() function to an actor, they'll act just as you expect as they are added and removed from the global list of actors.

## Starting with actors

compos loops over an "actors" array and runs the functions those actors and their components have registered for. For your entities to use the compos lifecycle, they will need to copy over the desired components and then be added to the global list of actors.

Here's an example of an object that draws an animating sprite in the middle of the screen:

```lua
local thingy = {
    physical = true, -- this inits the x, y, w, and y properties
    sprite = copy(sprite), -- this copies in the compo sprite component
    init = function(self) -- this runs on compo_init (or on demand if this actor is added with add_actor()
        translate(self, 60, 60) -- translate moves an actor to an x and y vector
        local spritesheet = split'0, 1, 2' -- split saves tokens by turning comma separated lists into arrays
        self.sprite:animate(self, spritesheet, 15, true) -- the third parameter is sprites-per-seocnd, the fourth is looping
    end
}
-- add to list of actors to be initialized and updated
add(actors, thingy)
```

Notice that the actor does not need to register any `update` or `draw` functions -- the `sprite` compo, when initialized, will register for all the lifecycle methods it requires.

If you're adding actors on the fly, use `add_actor()`. This method will run the required initialization and event registration before the actor is added to the scene.

## Lifecycle and the update pool

compos will handle their own updates, but you'll need to add compos functions somewhere for them to run. If nothing else, add the three basic functions to your cart:

```lua
function _init()
    compos_init()
end

function _update()
    compos_update()
end

function _draw()
    cls() -- compos doesn't clear for you!
    compos_draw()
end
```

Behind the scenes, within those `compos_*` functions, there are various "pools" of actors and compos that have registered to run each frame. The update functions availible are `early_update`, `update`, `late_update`, and `fixed_update`, and drawing is done in `early_update` and `update`.

When an actor is initialized, it's update functions are registered in those pools and run in the order they are added. Keep that in mind for drawing -- actors added later will be drawn on top. (Note that I want to add an optional override for this soon! For now you can use `early_draw` to make sure things are drawn in first.)

It's important to remove actors by using `remove_actor()`, as opposed to, say, `del(actors, thingy)`, because the `remove_actor` function also unregisters all events. Failing to use it could mean a memory leak as more and more actors are registered and none are rmeoved.

## Integrating compos into your project

The most direct way to integrate compos into your project is simply copy pasting all of compos.lua into your cart, then deleting unwanted components and functions

This can also be achieved using picotool, with some extra work. Just `require('compos.lua')` in your source pico8 file to include compos inside a "require" function. Just note that you'll need to delete the function wrapping the compo definitions for your code to reference them without errors. (NOTE: if you think I could get around this, let me know!)

You could also just hack the compo.p8 cart, using that as a jumping off point!

## Demo: Bouncy Blobs

Here's some code that uses compos to draw hundreds of actors with positions, sizes, colors, and gravity:

![Compos in action](bouncing-blobs.gif)

```lua
-- make actors as objects
-- copy compos to enable their functions
-- set compo values insite of init
-- include init(), update(), and draw() if this actor should have its own methods
local blob = {
    physical = true, -- this will add the properties x, y, w, and h (on compo init)
    velocity = copy(velocity),
    gravity = copy(gravity),
    collider = copy(collider),

    init = function(self)

        -- move it to a random position
        translate(self, rnd'128', 64)

        -- make a circle or a rect
        if flr(rnd'6') > 3 then
            resize(self, flr(rnd'8'+4))
        else
            resize(self, flr(rnd'8'+4), flr(rnd'8'+4))
        end

        self.collider:set(self)

        -- randomize the gravity on this object specifically
        self.gravity:set(max('0.025', rnd'0.05'))

        -- randomize inititial velocity and cap
        self.velocity:set(0,rnd'2'-1, vec(0.95, 1))
        self.velocity:cap(2,2)

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
local collider_blob = copy(blob)
collider_blob.sprite = copy(sprite)
collider_blob.init = function(self)
    self.color = 7
    resize(self, 16, 16)
    translate(self, 56, 56)
    self.velocity:set(1, 0)
    self.collider:set(self)
    self.gravity:set'0.1'
    self.outline = 0
    self.sprite:animate(self, split'0, 2, 0, 4', 1, true)
end

-- you can also register for special update stages
-- options are early_upate, late_update, and fixed_update (or early_draw!)
collider_blob.late_update = function(self)

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
end

-- if an actor has a "collision" function, it will check for collisions with other colliders every frame
-- all actors can have colliders at little cost, but too many "collision" functions add up!
collider_blob.collision = function(self, newvec, other)

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

-- add to compos actors
add(actors, collider_blob)

-- not all actors need compos!
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
```
