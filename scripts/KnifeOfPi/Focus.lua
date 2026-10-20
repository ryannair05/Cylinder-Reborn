--[[ ******************************************************************
Focus - modified Explosion by KnifeOfPi
******************************************************************* ]]

local abs, sqrt, pi = math.abs, math.sqrt, math.pi

return function(pg, of, sw, sh)

    local pc, cx, cy = abs(of/pg.width), pg.width/2, pg.height/2
    for i, ic in subviews(pg) do
        -- get icon center
        local icx, icy = ic:center()
        -- get icon offset from page center
        local ox, oy = cx-icx, cy-icy
        -- get hypotenuse
        local h = sqrt( ox^2+oy^2)
        -- move!
        ic:rotate(pc*pi/(0.0008*(h+200)), 0-ox, 0-oy, 0)
        -- if pc>0.6 then
            ic.alpha = 1-pc
        -- end
    end
end
