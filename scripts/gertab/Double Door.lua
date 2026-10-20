--[[
    Double Door
    by gertab

    improved by rweichler

    An effect which makes your icons look like a double door opening.
    Requested by; reddit.com/u/JerryD2T
]]

return function(page, offset, screen_width, screen_height)

    page:translate(offset)

    local width = page.width
    local percent = math.abs(offset/width)
    local middle = width/2
    for i, icon in subviews(page) do
        local x, w = icon.x, icon.width
        -- A widget that reaches past the middle moves farther, so it leaves the screen with its door.
        if x + w/2 > middle then
            icon:translate(percent*(width + 2*math.max(0, middle - x)))
        else
            icon:translate(-percent*(width + 2*math.max(0, x + w - middle)))
        end
    end

end
