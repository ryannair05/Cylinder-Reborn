local M_PI = math.pi

local function animateur(view, width, percent, is_inside)
    local angle = percent*M_PI
    local m = is_inside and 1/3 or -2/3
    local x = width * (percent < 0 and -0.5 or 0.5)
    
    for i, v in ipairs(view) do
        v:translate(3.5 * x, 0, 0)
        v:rotate(m * angle, 0, 1, 0)
        v:translate(-3.5 * x, 0, 0)
    end
end

return function(page, offset, width, height)
    animateur(page, width, offset/width, false)

    local percent = offset/width
    if percent < 0 then percent = -percent end

    page.alpha = 1 - percent^2
end
