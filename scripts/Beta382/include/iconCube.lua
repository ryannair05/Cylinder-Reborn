return function (page, iconNum, percent, isHorizontal, isForwards)
    local icon = page[iconNum]
    if not icon then return end
    
    local angle = percent * (math.pi / 2)
    local R = isHorizontal and page.width / 2 or page.height / 2
    local xOffset = page.width / 2 - icon.x - icon.width / 2
    local yOffset = page.height / 2 - icon.y - icon.height / 2
    
    icon.layer.x, icon.layer.y = icon.layer.x + xOffset, icon.layer.y + yOffset
    
    local ddirectional = -math.sin(angle) * R
    local dz = -(1 - math.cos(angle)) * R
    if not isForwards then
        ddirectional, angle = -ddirectional, -angle
    end
    
    if isHorizontal then
        icon:translate(ddirectional, 0, dz)
        icon:rotate(-angle, 0, 1, 0)
    else
        icon:translate(0, ddirectional, dz)
        icon:rotate(angle, 1, 0, 0)
    end
    
    icon:translate(-xOffset, -yOffset, 0)
    
    local threshold = math.abs(math.atan((PERSPECTIVE_DISTANCE - dz) / ddirectional))
    icon.alpha = math.abs(angle) > threshold and 1 - (math.abs(angle) - threshold) / (math.pi / 2 - threshold) or 1
end
