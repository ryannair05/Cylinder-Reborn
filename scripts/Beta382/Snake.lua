-- Icons travel along a boustrophedon path through the grid: left to right on even rows and right
-- to left on odd rows. The path only visits icons that exist, so widgets and sparse pages keep
-- the snake continuous.
return function(page, offset, screen_width, screen_height)
    local count = #page
    if count == 0 then return end

    local percent = math.abs(offset/page.width)
    local columns = math.max(page.max_columns, 1)

    -- Bucket each icon by its position along the path, then read the buckets in order.
    local slots = {}
    local slotKeys = {}
    for i = 1, count do
        local icon = page[i]
        local row, column = icon.row, icon.column
        if row % 2 == 1 then column = columns - 1 - column end
        local key = (row*columns + column)*count + i
        slots[key] = i
        slotKeys[#slotKeys+1] = key
    end
    table.sort(slotKeys)

    local path = {}
    local centersX, centersY = {}, {}
    for n, key in ipairs(slotKeys) do
        local icon = page[slots[key]]
        path[n] = icon
        centersX[n], centersY[n] = icon:center()
    end

    local lastRow = path[count].row
    local trailingDirection = lastRow % 2 == 0 and 1 or -1
    local finalIndex = count - 1
    local progress = percent*count
    local exitDistance = 2.5*page.width/columns

    for n, icon in ipairs(path) do
        local target = (n - 1) + (offset >= 0 and progress or -progress)
        local x, y
        if target < 0 then
            x = centersX[1] + target*exitDistance
            y = centersY[1]
        elseif target > finalIndex then
            x = centersX[count] + (target - finalIndex)*exitDistance*trailingDirection
            y = centersY[count]
        else
            local lower = math.floor(target)
            local upper = math.min(lower + 1, finalIndex)
            local fraction = target - lower
            x = centersX[lower+1] + (centersX[upper+1] - centersX[lower+1])*fraction
            y = centersY[lower+1] + (centersY[upper+1] - centersY[lower+1])*fraction
        end
        icon:translate(x - centersX[n], y - centersY[n], 0)
    end

    page:translate(offset, 0, 0)
end
