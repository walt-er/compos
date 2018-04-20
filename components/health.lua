-- //////////////
-- health
-- //////////////

compos.health = {
    total = -999,
    max = 0,
    set = function(self, new_health)
        self.max, self.total = max(0, new_health), max(0, new_health)
    end,
    damage = function(self, damage)
        self.total, self.damage_time = self.total - damage, time()
    end,
    update = function(self, parent)

        -- store life as flag on parent, call death function
        parent.alive = self.total > 0

        -- show health bar when damaged
        self.show_health = self.damage_time and time() - self.damage_time < 2 and parent.alive

    end,
    late_draw = function(self, parent)
        if self.show_health and self.total > 0 then

            -- calculate position of health bar to draw
            local start_x, start_y, end_x, end_y = parent.x - 2, parent.y - 8, parent.x + parent.w + 2, parent.y - 6

            -- get end x for fill representing remaining health
            local fill_end_x = start_x + flr((end_x - start_x) * (self.total / self.max))

            -- draw health bar
            outline_rect(start_x, start_y, end_x, end_y, 6, 1)
            line(start_x, end_y, end_x, end_y, 13)
            outline_rect(start_x, start_y, fill_end_x, end_y, 8)
            line(start_x, start_y, fill_end_x, start_y, 14)

        end
    end
}

function hurt(actor, attack)
    if
		attack.armed
        and actor.health
        and actor.health.total > 0
    then

        -- if valid target, hurt actor and remove attack object
        actor.health:damage(attack.damage)
        if (actor.sprite and actor.health.total > 0) actor.sprite:flash()
		attack.armed = false

    end
end
