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
