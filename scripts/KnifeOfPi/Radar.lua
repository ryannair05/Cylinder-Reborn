--[[ ******************************************************************
Radar by KnifeOfPi

******************************************************************* ]]

local abs, sqrt, sin, cos, atan, min, pi = math.abs, math.sqrt, math.sin, math.cos, math.atan, math.min, math.pi

return function(pg, of, sw, sh)
    pg:translate(of, 0, 0)

    local pc = abs(of / pg.width)
    local cx, cy = pg.width / 2, pg.height / 2
    local ops = of / pg.width
    local midx = pg.width / 2
    local midy = pg.height / 2 + 7
    local fx = min(pc * 5, 1)
    local r = (ops < 0) and -1 or 1

    for i, ic in subviews(pg) do
        -- get icon center
        local icx, icy = ic:center()
        -- get icon offset from page center
        local ox, oy = cx - icx, cy - icy
        -- get angle of icon position
        local ang = atan(oy, ox)
        -- get hypotenuse
        local h = sqrt(ox^2 + oy^2)

        local an = ang - 0.5 * pi
        if an > 0 and r == 1 then an = an - 2 * pi end
        if an < 0 and r == -1 then an = an + 2 * pi end

        -- calc new x & y
        local go = -2 * pc * an + ang
        local nx = -h * cos(-go)
        local ny = -h * sin(go)

        -- move!
        ic:translate(fx*(nx-icx+midx),fx*(ny-icy+midy),0)

        -- if pc > 0.6 then
        ic.alpha = 1 - 2 * pc
        -- end
    end
end
