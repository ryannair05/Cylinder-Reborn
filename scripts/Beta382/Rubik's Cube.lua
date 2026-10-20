local iconCube = dofile("include/iconCube.lua")
local min, max = math.min, math.max

return function(page, offset, screen_width, screen_height)
    local maxRows = page.max_rows

    -- A value from 0 to 1 that specifies how long each row should take to complete animating
    -- Change this and only this, hackers
    local animationDuration = 1/maxRows

    local percent = offset/page.width
    local lastRow = maxRows-1
    local rowSpan = max(lastRow, 1)

    for i, icon in subviews(page) do
        local iconRow = min(max(icon.row, 0), lastRow)

        local curRowStartP = (1-animationDuration)*(iconRow/rowSpan)

        if (offset < 0) then
            curRowStartP = curRowStartP-1+animationDuration
        end

        local iconCurPercent = (percent-curRowStartP)*(1/animationDuration)

        if (offset >= 0) then
            if (iconCurPercent > 1) then iconCurPercent = 1
            elseif (iconCurPercent < 0) then iconCurPercent = 0 end
        elseif (offset < 0) then
            if (iconCurPercent < -1) then iconCurPercent = -1
            elseif (iconCurPercent > 0) then iconCurPercent = 0 end
        end

        iconCube(page, icon, iconCurPercent, true, true)
    end

    page:translate(offset, 0, 0)
end
