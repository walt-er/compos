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
