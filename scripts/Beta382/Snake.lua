return function (page, offset, screen_width, screen_height)
    local percent = math.abs(offset/page.width)
    
    -- Calculate grid layout parameters
    local gridParams = {
        topLeftX = 0,
        topLeftY = 0,
        maxColumnWidth = 0,
        maxRowHeight = 0,
        columnSpacing = 0,
        rowSpacing = 0
    }
    
    -- First pass: find maximum dimensions and spacing
    if page[1] then
        gridParams.topLeftX = page[1].x
        gridParams.topLeftY = page[1].y
        
        -- Calculate maximum dimensions per column and row
        local columnWidths = {}
        local rowHeights = {}
        
        for i = 1, #page.subviews do
            local icon = page[i]
            if icon then
                local columnIndex = ((i-1) % page.max_columns) + 1
                local rowIndex = math.floor((i-1) / page.max_columns) + 1
                
                -- Track maximum width for each column
                columnWidths[columnIndex] = columnWidths[columnIndex] or 0
                columnWidths[columnIndex] = math.max(columnWidths[columnIndex], icon.width)
                
                -- Track maximum height for each row
                rowHeights[rowIndex] = rowHeights[rowIndex] or 0
                rowHeights[rowIndex] = math.max(rowHeights[rowIndex], icon.height)
            end
        end
        
        -- Calculate spacing between columns
        local totalColumnSpacing = 0
        local spacingCount = 0
        for i = 2, #page.subviews do
            local curr = page[i]
            local prev = page[i-1]
            if curr and prev and ((i-1) % page.max_columns) ~= 0 then
                local spacing = curr.x - (prev.x + prev.width)
                totalColumnSpacing = totalColumnSpacing + spacing
                spacingCount = spacingCount + 1
            end
        end
        gridParams.columnSpacing = spacingCount > 0 and (totalColumnSpacing / spacingCount) or 0
        
        -- Calculate spacing between rows
        local totalRowSpacing = 0
        spacingCount = 0
        for i = (page.max_columns + 1), #page.subviews do
            local curr = page[i]
            local prev = page[i - page.max_columns]
            if curr and prev then
                local spacing = curr.y - (prev.y + prev.height)
                totalRowSpacing = totalRowSpacing + spacing
                spacingCount = spacingCount + 1
            end
        end
        gridParams.rowSpacing = spacingCount > 0 and (totalRowSpacing / spacingCount) or 0
        
        -- Calculate maximum dimensions
        for _, width in pairs(columnWidths) do
            gridParams.maxColumnWidth = math.max(gridParams.maxColumnWidth, width)
        end
        for _, height in pairs(rowHeights) do
            gridParams.maxRowHeight = math.max(gridParams.maxRowHeight, height)
        end
    end
    
    -- Process each icon
    local i = 0
    while true do
        i = i + 1
        local icon = page[i]
        if not icon then break end
        
        local iconIndex = i
        local iconRowNum = math.floor((iconIndex-1)/page.max_columns)
        
        -- Reverse index for odd rows
        if iconRowNum % 2 == 1 then
            iconIndex = iconRowNum * page.max_columns + (page.max_columns - ((iconIndex-1) % page.max_columns) - 1) + 1
        end
        
        -- Calculate animation parameters
        local iconPercent = percent + (offset >= 0 and 
            ((iconIndex-1)/page.max_icons) or 
            ((page.max_icons-iconIndex)/page.max_icons))
        
        local iconCurRowNum = math.min(
            math.floor((iconPercent*page.max_icons)/page.max_columns),
            page.max_rows-1
        )
        
        -- Determine direction
        local direction = 1
        if offset >= 0 then
            if iconCurRowNum % 2 == 1 then direction = -1 end
        else
            if (page.max_rows-iconCurRowNum-1) % 2 == 0 then direction = -1 end
        end
        
        -- Calculate row and column percentages
        local percentForRow = 1/page.max_rows
        local percentThroughRow = (iconPercent-(percentForRow*iconCurRowNum))*(1/(percentForRow-(percentForRow/page.max_columns)))
        
        if percentThroughRow > 1 then 
            percentThroughRow = 1
        elseif percentThroughRow < 0 then 
            percentThroughRow = 0 
        end
        
        if iconPercent > (page.max_icons-1)/page.max_icons then 
            percentThroughRow = 1 + (iconPercent-((page.max_icons-1)/page.max_icons))*(2.5/(percentForRow-(percentForRow/page.max_columns)))
        end
        if direction < 0 then percentThroughRow = 1-percentThroughRow end
        
        -- Calculate travel distances using actual spacing and maximum dimensions
        local maxTravelDistanceX = (gridParams.maxColumnWidth + gridParams.columnSpacing) * (page.max_columns - 1)
        local maxTravelDistanceY = (gridParams.maxRowHeight + gridParams.rowSpacing) * (page.max_rows - 1)
        
        -- Calculate Y movement
        local percentThroughColumn = iconCurRowNum/(page.max_rows-1)
        if (percentForRow-(iconPercent-(percentForRow*iconCurRowNum)) < 1/page.max_icons) then
            percentThroughColumn = percentThroughColumn + 
                (((iconPercent-(percentForRow*iconCurRowNum))-((1/page.max_icons)*(page.max_columns-1)))*page.max_icons)/(page.max_rows-1)
        end
        
        if percentThroughColumn > 1 then 
            percentThroughColumn = 1
        elseif percentThroughColumn < 0 then 
            percentThroughColumn = 0 
        end
        
        if offset < 0 then percentThroughColumn = 1-percentThroughColumn end
        
        -- Calculate final positions with centering offset for different sized icons
        local endX = (percentThroughRow * maxTravelDistanceX) + gridParams.topLeftX + 
                    (gridParams.maxColumnWidth - icon.width) / 2
        local endY = (percentThroughColumn * maxTravelDistanceY) + gridParams.topLeftY + 
                    (gridParams.maxRowHeight - icon.height) / 2
        
        -- Apply translation
        icon:translate(endX - icon.x, endY - icon.y, 0)
    end
    
    page:translate(offset, 0, 0)
end