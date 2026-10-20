--[[ ******************************************************************
Burst by KOP
******************************************************************* ]]

local abs, sqrt, atan, min, pi = math.abs, math.sqrt, math.atan, math.min, math.pi

return function(pg, of, sw, sh)
    local pc, cx, cy = abs(of/pg.width), pg.width/2, pg.height/2
    -- target distance
    local tg = pg.width
    local fx = min(5 * pc, 1)
    local de = min(3 * pc, 1)
    local stretch = fx*(1.5^(3*pc+1)-3.4*de^0.33)

    for i, ic in subviews(pg) do
        -- get icon center
        local icx, icy = ic:center()
        -- get icon offset from page center
        local ox, oy = cx-icx, cy-icy
        local ax, ay = abs(ox), abs(oy)
        -- get angle of icon position
        local ang = atan(oy,ox)
        -- get hypotenuse
        local h = sqrt( ox^2+oy^2)
        -- get hypotenuse extension
        local oh = pc*tg+stretch*h
        -- directions
        local dx = (icx < cx) and -1 or 1
        local dy = (icy < cy) and -1 or (icy == cy and 0 or 1)
        -- cosine and sine of the icon's angle from the page center
        local cosine, sine = 1, 0
        if h > 0 then cosine, sine = ax/h, ay/h end
        -- calc new x & y
        local nx = oh * cosine * dx
        local ny = oh * sine * dy

        -- move!
        ic:translate(nx, ny)
        if oy >= 0 then
            ic:rotate(fx*(ang-.5*pi), 0, 0, 1)
        else
            ic:rotate(fx*(ang+.5*pi), 0, 0, 1)
        end
        local tilt = pc*(380/(h+20)^0.8)
        ic:rotate(tilt, oy, 0, 0)
        if oy==0 then
            ic:rotate(tilt, ox, 0, 0)
        end
        --ic:rotate(, 0, 0-oy, 0)
        -- if pc>0.6 then
            ic.alpha = 1-pc
        -- end
    end
end
