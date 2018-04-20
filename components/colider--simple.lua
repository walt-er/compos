-- //////////////
-- collisions for rects only
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
        if rect_overlap(parent_col, other_col) then

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
            rect(parent.x + self.offset.x, parent.y + self.offset.y, parent.x + self.offset.x + self.w, parent.y + self.offset.y + self.h, 11)
        end
    end
}
