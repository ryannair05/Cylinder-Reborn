local abs, min, max = math.abs, math.min, math.max

return function(page, offset, screen_width, screen_height)
    local percent = abs(offset/page.width)
    local width = page.width

    -- An unresolved grid reports zero cells, which would divide by zero below.
    local numIcons = max(page.max_icons, 1)
    local columns = page.max_columns
    local step = 0.525/numIcons

    for i, icon in subviews(page) do
        -- Widgets span several cells, so an icon's place in the wave comes from its grid cell.
        local gridIndex = min(max(icon.row*columns + icon.column, i-1), numIcons-1)
        local direction = -1
        local iconIndex = gridIndex
        if (offset < 0) then
            direction = 1
            iconIndex = numIcons-gridIndex-1
        end

        local curIconPercent = percent-(step*iconIndex)

        if (curIconPercent > 0) then
            local dx = direction*(curIconPercent*3.5^2)*width

            icon:translate(dx, 0, 0)
        end
    end

    page:translate(offset, 0, 0)
end
