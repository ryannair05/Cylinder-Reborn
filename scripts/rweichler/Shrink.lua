



return function(page, offset, screen_width, screen_height)

    local percent = offset/page.width
    local size = 1-math.abs(percent)

    for i, icon in subviews(page) do
        icon:scale(size)
    end


end
