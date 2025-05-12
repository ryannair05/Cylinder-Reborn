--[[ ******************************************************************
Radar by KnifeOfPi
                
******************************************************************* ]]

return function(pg, of, sw, sh)
    pg:translate(of, 0, 0)

    local pc = math.abs(of / pg.width)
    local cx, cy = pg.width / 2, pg.height / 2
    local ops = of / pg.width
    -- target distance
    local midx = pg.width / 2
    local midy = pg.height / 2 + 7
    local tg = pg.width
    local fx = math.min(pc * 5, 1)

    for i, ic in subviews(pg) do
        -- get icon center
        local icx, icy = ic.x + ic.width / 2, ic.y + ic.height / 2
        -- get icon offset from page center
        local ox, oy = cx - icx, cy - icy
        -- get angle of icon position
        local ang = math.atan(oy, ox)
        -- get hypotenuse
        local h = math.sqrt(ox^2 + oy^2)

        local iconX = ic.x+ic.width/2
        local fall = (1-pc^2)*h
        local iconY = ic.y+ic.height/2
        -- get hypotenuse extension
        local nh = math.sqrt((iconX-midx)^2+(iconY-midy)^2)
        local oh = fx*h+fx*tg
        -- directions
        local dx, dy = 1, 1
        local dxz, dyz = 1, 1

        if icx < cx then dx, dxz = 0, 1 end
        if icx > cx then dx, dxz = -1, -1 end
        if icy < cy then dy, dyz = 0, 1 end
        if icy > cy then dy, dyz = -1, -1 end
        if icy == cy then dy = 1 end

        local r = (ops < 0) and -1 or 1
        local an = ang - 0.5 * math.pi
        if an > 0 and r == 1 then an = an - 2 * math.pi end
        if an < 0 and r == -1 then an = an + 2 * math.pi end

        -- calc new x & y
        local go = -2 * pc * an + ang
        local nx = -h * math.cos(-go)
        local ny = -h * math.sin(go)
        local size = math.min((3 - fx) * (fall / h), 1)

        -- move!
        ic:translate(fx*(nx-iconX+midx),fx*(ny-iconY+midy),0)
        -- ic:scale(size * size)
        -- ic:translate(-0.5 * nx, -0.5 * ny, 0)

        -- if pc > 0.6 then
        ic.alpha = 1 - 2 * pc
        -- end
    end
end
