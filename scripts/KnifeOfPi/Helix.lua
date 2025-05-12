--[[ ******************************************************************
Double Helix by KOP
        
******************************************************************* ]]

return function(pg, of, sw, sh)
    local pc = math.abs(of / pg.width)
    local cx, cy = pg.width / 2, pg.height / 2
    local ops = of / pg.width
    -- target distance
    local midx = pg.width / 2
    local midy = pg.height / 2 + 7
    local tg = pg.width
    local fx = math.min(math.max(pc * 5, -1), 1)
    local to = pc

    -- if(of > 0) then side = 1 end
    for i, ic in subviews(pg) do
        -- get icon center
        local icx, icy = (ic.x+ic.width/2), (ic.y+ic.height/2)
        -- get icon offset from page center
        local ox, oy = cx-icx, cy-icy
        -- get angle of icon position
        local ang = math.atan(oy,ox)
        -- get hypotenuse
        local h = math.sqrt(ox^2 + oy^2)
        local fall = (1 - pc) * h
        -- get hypotenuse extension
        local oh = fx*h+fx*tg
        -- directions
        local dx = (icx < cx) and -1 or 1
        local dy = (icy < cy) and -1 or 1
        if icy == cy then dy = 0 end
        local cy = math.min(3 - 3 * pc, 1)
        if pc == 0 then pc = 0.0001 end

        -- calc new x & y
        local nx = midx - ops / pc * (pg.width / (7.5 - pg.max_columns)) * math.sin(ops * 4 * math.pi + 8 * (oy - (1 / pg.max_columns * ox)) / 1.33 / pg.height)
        local ny = midy - oy + (1 / pg.max_columns) * ox

        -- Prevent overlapping by slightly adjusting positions based on index
        local offset = i * 0.1
        nx = nx + offset
        ny = ny + offset

        -- move!!
        ic:translate(fx * (nx - icx), fx * (ny - icy), 0)
        ic:rotate(fx * (ops * 4 * math.pi + 0.5 * ops / pc * math.pi + 8 * (oy - (1 / pg.max_columns * ox)) / 1.33 / pg.height), 0, 1, 0)
    end
end