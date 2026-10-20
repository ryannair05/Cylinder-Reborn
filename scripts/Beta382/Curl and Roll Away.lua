local abs, sin, cos, min, max, pi = math.abs, math.sin, math.cos, math.min, math.max, math.pi

return function(page, offset, screen_width, screen_height)
    local percent = abs(offset/page.width)

    local centerX = page.width/2
    local centerY = page.height/2+7
    local radius = 0.30*page.width
    if radius > page.height then radius = 0.30*page.height end

    local theta = (2*pi)/#page

    local stage1P = min(percent * 2, 1)
    local stage2P = max(min((percent - 0.5) * 2, 1), 0)

    for i, icon in subviews(page) do
        local iconAngle = theta*(i-1)+stage2P*(pi/2)

        local begX, begY = icon:center()

        local endX = centerX+radius*cos(iconAngle)
        local endY = centerY-radius*sin(iconAngle)

        icon:translate((endX-begX)*stage1P, (endY-begY)*stage1P, 0)
        icon:rotate(-stage1P*((pi/2) + iconAngle))
    end
end
