-- =======================================================
-- drawing helpers
-- =======================================================

local transparent = 11 -- change this to whatever color you use as transparent in your sprites
function set_transparent_colors()
	pal()
    palt(0, false)
    palt(transparent, true)
end

function outline_print(s, x, y, color, outline)
	local outline = outline or 0
    for i = -1, 1 do
        for j = -1, 1 do
            if not(i == j) then
                print(s,x+i,y+j,outline)
            end
        end
    end
    print(s, x, y, color)
end

function outline_rect(x, y, x2, y2, fill, outline)
    local outline = outline or 0
    rectfill(x, y-1, x2, y2+1, outline)
    rectfill(x-1, y, x2+1, y2, outline)
    rectfill(x, y, x2, y2, fill)
end

function outline_circ(x, y, r, fill, outline)
    local outline = outline or 0
    circfill(x,y,r+1,outline)
    circfill(x,y,r,fill)
end

-- zoom a sprite to fill an area
function zspr(n, dx, dy, w, h, flip_x, flip_y, dz)
	if not(dz) or dz==1 then
		spr(n,dx,dy,w,h,flip_x,flip_y)
    elseif n >= 0 then
        sx, sy, sw, sh = shl(band(n, 0x0f), 3), shr(band(n, 0xf0), 1), shl(w, 3), shl(h, 3)
		dw, dh = sw * dz, sh * dz
        sspr(sx,sy,sw,sh,dx,dy,dw,dh,flip_x,flip_y)
    end
end

function outline_spr(id, x, y, w, h, outline, fill, flip_x, flip_y, zoom, color_map)

    -- don't outline
	if outline == -1 then
        set_transparent_colors()
        zspr(id, x, y, w, h, flip_x, flip_y, zoom)
	else

        -- change all colors to outline color
        local outline = outline or 0
        for i=1, 15 do
            if (i ~= transparent) pal(i, outline)
        end

        -- draw outline sprites
        for i = -1, 1 do
            for j = -1, 1 do
                if not(abs(i) == abs(j)) then
                    zspr(id, x+i, y+j, w, h, flip_x, flip_y, zoom)
                end
            end
        end

        -- reset palette
        set_transparent_colors()

        if fill then

            -- change all colors to fill color
            for i=0, 15 do
                if (i ~= transparent) pal(i, fill)
            end

        elseif color_map then

            -- map colors to other colors
            pal(color_map[1], color_map[2])

        end

        -- draw!
        zspr(id, x, y, w, h, flip_x, flip_y, zoom)

        -- reset palette
        set_transparent_colors()

    end
end

-- fill with sprite pattern (not 100% accurate?)
function spritefill(rectangle, id, pattern_width)
	pattern_width = pattern_width or 1;
	for i = 0, flr(rectangle.w / (tile * pattern_width)) - 1 do
		for j = 0, flr(rectangle.h / (tile * pattern_width)) - 1 do
			spr(id, rectangle.x + (i * (tile * pattern_width)), rectangle.y + (j * (tile * pattern_width)))
		end
	end
end
