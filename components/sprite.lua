-- //////////////
-- sprite (requires core/drawing)
-- //////////////

compos.sprite = {
	id = 0,
    loop = false,
    zoom = 1,
    animating = false,
    frame = 0.1,
    flipped = false,
	flip_y = false,
    flash_count = -1,
	outline = 0,
    old_fill = -1,
    old_outline = -1,

    set = function(self, id, size, zoom)
        self.id = id
		if (size) then
			self.w = size.x
			self.h = size.y
		end
		self.zoom = zoom
    end,

    animate = function(self, parent, spritesheet, fps, loop, zoom)
        self.animating, self.loop, self.sheet, self.frame, self.fps, self.zoom, self.t = true, loop, spritesheet, 0.1, fps, zoom or 1, time()
    end,

    stop_animation = function(self)
        self.sheet, self.animating = {}, false
    end,

    flash = function(self, color, outline, count, frame_length)
        self.flashes, self.flashing, self.flash_color, self.flash_outline, self.flash_frame_length = 0, false, color or 8, outline or 2, frame_length or 3
		self.flash_count = count or self.flash_frame_length
    end,

    reset_flash = function(self)
        self.fill, self.outline, self.flashing, self.old_fill, self.old_outline, self.flash_count = self.old_fill, self.old_outline, false, -1, -1, -1
    end,

	init = function(self, parent)

		self.flipped = parent.flipped

		if parent.background then
			self.background_draw = self.draw_sprite
		elseif parent.early then
			self.early_draw = self.draw_sprite
		elseif parent.foreground then
			self.late_draw = self.draw_sprite
		else
			self.draw = self.draw_sprite
		end

	end,

    update = function(self, parent)

		local sheet = self.sheet

        -- loop over spritesheet if it exists
        if sheet and #sheet > 0 then

            -- iterate over frames
            local frame = (time() - self.t) * self.fps
            frame = self.loop and frame % #sheet or min(#sheet, frame)

            -- set new frame
            self.id = sheet[max(1, ceil(frame))] + 0

            -- stop animation (if not looping) at end of sheet
            if (not(self.loop) and frame >= #sheet) self:stop_animation()

        end

        -- flash
        if self.flash_count > -1 and self.flashes < self.flash_count then
            if not(self.flashing) then

                if (self.old_fill == -1) then
                    self.old_fill = self.fill or nil
                    self.old_outline = self.outline + 0 or nil
                end

                self.fill = self.flash_color
                self.outline = self.flash_outline
                self.flashes += 1
                if (self.flashes % self.flash_frame_length == 0) self.flashing = true
            else
                self:reset_flash()
            end
        elseif self.flash_count ~= -1 then
            self:reset_flash()
        end

    end,

	draw_sprite = function(self, parent)
		self.w = self.w or parent.w
		self.h = self.h or parent.h
		self.zoom = self.zoom or 1

        -- render selected sprite at position
		local parent_x = parent.adjusted_x or parent.x
        local parent_y = parent.adjusted_y or parent.y
		local spr_x = parent_x + (parent.w / 2) - (self.w / 2)
		local spr_y = parent_y + (parent.h / 2) - (self.h / 2)

        -- draw the sprite!
        outline_spr(
            self.id,
            spr_x,
            spr_y,
            (self.w / tile) / self.zoom,
            (self.h / tile) / self.zoom,
            self.outline,
            self.fill,
            self.flipped,
            self.flip_y,
            self.zoom,
            self.color_map
        )
    end
}