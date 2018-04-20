-- //////////////
-- parallax
-- //////////////

compos.parallax = {
    set = function(self, parent, depth)
        parent.depth = depth or 0
        self:adjust_position(parent)
    end,
    adjust_position = function(self, parent)
        newcoords = parent.velocity and parent.velocity.newvec or parent
        parent.adjusted_x = newcoords.x - ((parent.depth * ((cam.x + 64) - newcoords.x)) / 100)
        parent.adjusted_y = newcoords.y - ((parent.depth * ((cam.y + 64) - newcoords.y)) / 100)
    end,
    fixed_update = function(self, parent)
        self:adjust_position(parent)
    end
}