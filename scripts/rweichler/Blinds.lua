local icon_random = dofile("include/icon_random.lua")
local abs, pi = math.abs, math.pi

local function blind(icon, percent)
    icon:rotate(pi*percent, 0, 1, 0)
    if abs(percent) >= 0.5 then
        icon.alpha = 0
    else
        icon.alpha = 1
    end
    --icon.alpha = 1 - abs(percent)
end

return function(page, offset, screen_width, screen_height)

    --magnitude = 0, not subtle at all
    --magnitude = 1, so subtle you don't even notice it
    local magnitude = 0.8

    icon_random(page, offset/page.width, magnitude, blind)

end
