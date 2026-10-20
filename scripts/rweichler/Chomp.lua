return function(page, offset, screen_width, screen_height)
    local percent = offset/page.width

    if percent < 0 then percent = -percent end

    local middle = page.height/2

    for i, icon in subviews(page) do
        local mult = 1
        local _, y = icon:center()
        if y < middle then mult = -1 end
        icon:translate(0, mult*percent*screen_height/2, 0)
    end

end
