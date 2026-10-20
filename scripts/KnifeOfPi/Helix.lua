--[[ ******************************************************************
Double Helix by KOP

******************************************************************* ]]

local abs, sin, min, max, pi = math.abs, math.sin, math.min, math.max, math.pi

return function(pg, of, sw, sh)
    local width, height = pg.width, pg.height
    local pc = abs(of / width)
    local cx, cy = width / 2, height / 2
    local ops = of / width
    -- target distance
    local midx = width / 2
    local midy = height / 2 + 7
    local fx = min(max(pc * 5, -1), 1)

    -- An unresolved grid reports zero columns, which would divide by zero below.
    local columns = max(pg.max_columns, 1)
    local inverseColumns = 1 / columns
    local amplitude = width / (7.5 - columns)
    -- The scroll direction, which stays finite while the page is at rest.
    local direction = ops / (pc == 0 and 0.0001 or pc)
    local spin = ops * 4 * pi
    local twist = spin + 0.5 * direction * pi

    for i, ic in subviews(pg) do
        -- get icon center
        local icx, icy = ic:center()
        -- get icon offset from page center
        local ox, oy = cx-icx, cy-icy
        local phase = 8 * (oy - (inverseColumns * ox)) / 1.33 / height

        -- calc new x & y
        local nx = midx - direction * amplitude * sin(spin + phase)
        local ny = midy - oy + inverseColumns * ox

        -- Prevent overlapping by slightly adjusting positions based on index
        local offset = i * 0.1
        nx = nx + offset
        ny = ny + offset

        -- move!!
        ic:translate(fx * (nx - icx), fx * (ny - icy), 0)
        ic:rotate(fx * (twist + phase), 0, 1, 0)
    end
end
