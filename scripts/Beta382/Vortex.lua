local abs, sin, cos, min, max, pi = math.abs, math.sin, math.cos, math.min, math.max, math.pi

return function(page, offset, screen_width, screen_height)
    local percent = abs(offset/page.width)

    local centerX = page.width/2
    local centerY = page.height/2+7
    local radius = 0.60*page.width/2
    if radius > page.height then radius = 0.60*page.height/2 end

    local theta = (2*pi)/#page

    local endStage1P = 1/3

    local stage1P = min(percent * 3, 1)
    local stage2P = max(min((percent - endStage1P) * 3, 1), 0)

    for i, icon in subviews(page) do
        local iconAngle = theta*(i-1) - pi/6 + stage2P*(pi/3)

        local begX, begY = icon:center()

        local endX = centerX+radius*cos(iconAngle)
        local endY = centerY-radius*sin(iconAngle)

        icon:translate((endX-begX)*stage1P, (endY-begY)*stage1P, 0)
        icon:rotate(-stage1P*((pi/2) + iconAngle))
    end

    page.alpha = 1 - stage2P
    page:translate(offset, 0, 0)
end
