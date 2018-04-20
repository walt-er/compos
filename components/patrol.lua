-- //////////////
-- patrol
-- //////////////

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
