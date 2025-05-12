local function swing(page, percent, height, width,offset)
    for i = 1, #page do
        local icon = page[i]
        icon:translate(percent*width, 0)
    end
    page:translate(0,0,-percent*400)
end
local function fade(view, percent)
    view.alpha = 1 - math.abs(percent)
end
return function(page, offset, screen_width, screen_height)
    local percent = offset/page.width
    swing(page, percent, page.height, page.width)
    fade(page,percent)
end
