local sin, cos, abs, atan = math.sin, math.cos, math.abs, math.atan
local HALF_PI = math.pi / 2

return function (page, icon, percent, isHorizontal, isForwards)
    local angle = percent * HALF_PI
    local width, height = page.width, page.height
    local R = isHorizontal and width / 2 or height / 2
    local centerX, centerY = icon:center()
    local xOffset = width / 2 - centerX
    local yOffset = height / 2 - centerY

    local layer = icon.layer
    layer.x, layer.y = layer.x + xOffset, layer.y + yOffset

    local ddirectional = -sin(angle) * R
    local dz = -(1 - cos(angle)) * R
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

    local threshold = abs(atan((PERSPECTIVE_DISTANCE - dz) / ddirectional))
    icon.alpha = abs(angle) > threshold and 1 - (abs(angle) - threshold) / (HALF_PI - threshold) or 1
end
