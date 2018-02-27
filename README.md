# compos
A suite of reusable components for PICO-8

The most direct way to integrate compos into your project is simply copy pasting all of compos.lua into your cart, then deleting unwanted components and functions

This can also be achieved using picotool, with some extra work. Just `require('compos.lua')` in your source pico8 file to include compos inside a "require" function. Just note that you'll need to delete the function wrapping the compo definitions for your code to reference them without errors.

You could also just hack compo.p8, using that as a jumping off point!

Here's some code that uses compos to draw hundreds of actors with positions, sizes, colors, and gravity:

![Compos in action](https://raw.githubusercontent.com/walt-er/compos/compos.gif)

```
-- make actors as objects
-- copy compos to enable their functions
-- set compo values insite of init
-- include init(), update(), and draw() if this actor should have its own methods
local blob = {
    physical = true, -- this will add the properties x, y, w, and h (on compo init)
    velocity = copy(velocity),
    gravity = copy(gravity),
    init = function(self)

        -- make a circle or a rect
        self.circle = flr(rnd(2)) > 0
        if self.circle then
            self.r = rnd(8)
        else
            resize(self, rnd(16), rnd(16))
        end

        -- move it to a random position
        translate(self, rnd(128), 64)

        -- randomize the gravity on this object specifically
        self.gravity:set(rnd(3) / 5)

        -- randomize inititial velocity and cap
        self.velocity:set(0,rnd(10)-5)
        self.velocity:cap(0,15)
    end,
    update = function(self)
        -- reverse velocity if below window bottom
        if self.y + self.h > win_h then
            translate(self, self.x, win_h - self.h)
            self.velocity:set(0, -6)
        end
    end,
    draw = function(self)
        -- draw the shape during the draw function
        if self.circle then
            outline_circ(self.x, self.y, self.r, self.color, 6)
        else
            outline_rect(self.x, self.y, self.x + self.w, self.y + self.h, self.color, 6)
        end
    end
}

-- "split" is a handy method for reducing lengthy objects into 2-token function calls
local blob_colors = split'0, 1, 2, 13'

-- add these objects to the list of actors
local blob_count = 400
for i = 1, blob_count do
    -- assign a color based on depth
    blob.color = blob_colors[ ceil((i / blob_count) * (#blob_colors)) ]
    add(actors, copy(blob))
end

-- not all actors need compos!
local title_text = {
    update = function(self)
        self.y = 64 + sin(time()) * 8

        -- debugging: log out the y to see where the text is
        -- log(self.y)
    end,
    draw = function(self)
        local message = 'compos!'
        outline_print(message, 64 - #message * 2, self.y, 7, 8)
    end
}
add(actors, title_text)

-- pico8 lifecycle functions
-- call compos_* functions or add other scene logic
function _init()
    compos_init()
end

function _update()
    compos_update()

    -- log out performance
    log('actors: '..blob_count+1)
    log('fps: '..stat(7))
end

function _draw()
    cls()
    compos_draw()
end
```