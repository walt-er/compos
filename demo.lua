require('compos')

-- =======================================================
-- demo!
-- =======================================================

-- make actors as objects
-- copy compos to enable their functions
-- set compo values insite of init
-- include init(), update(), and draw() if this actor should have its own methods
local blob_colors = split'0, 1, 2'
local blob = {
    physical = true,
    velocity = copy(velocity),
    gravity = copy(gravity),
    init = function(self)
        self.circle = flr(rnd(2)) > 0
        if self.circle then
            self.r = rnd(16)
        else
            resize(self, rnd(16), rnd(16))
        end

        translate(self, rnd(128), 64)
        self.color = blob_colors[ ceil(rnd(#blob_colors)) ]

        self.gravity:set(0.1)

        self.velocity:set(0,rnd(20)-10)
        self.velocity:cap(0,15)
    end,
    update = function(self)
        if self.y > win_h then
            translate(self, rnd(128), 128)
            self.velocity:set(0, rnd(5)-5)
        end
    end,
    draw = function(self)
        if self.circle then
            outline_circ(self.x, self.y, self.r, self.color, 6)
        else
            outline_rect(self.x, self.y, self.x + self.w, self.y + self.h, self.color, 6)
        end
    end
}

-- add these objects to the list of actors
local blob_count = 300
for i = 1, blob_count do
    add(actors, copy(blob))
end

-- not all actors need compos!
local title_text = {
    update = function(self)
        self.y = 64 + sin(time()) * 8

        --debugging: log out the y to see where the text is
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
    for i=0,1000 do
        circ(rnd(128),rnd(128),1,0)
    end

    compos_draw()
end