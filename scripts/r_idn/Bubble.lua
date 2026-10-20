local icon_random = dofile("../rweichler/include/icon_random.lua")
local abs = math.abs

local function grow(icon, percent)
    icon:scale(1+abs(percent/2.5))
end

return function(page, offset, screen_width, screen_height)
    local magnitude = 0.4
    icon_random(page, offset/page.width, magnitude, grow)
end
