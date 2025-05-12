return function(page, offset, screen_width, screen_height)
    local percent = math.abs(offset/page.width)
    
    local centerX = page.width/2
    local centerY = page.height/2+7
    local radius = 0.60*page.width/2
    if radius > page.height then radius = 0.60*page.height/2 end
    
    local theta = (2*math.pi)/#page.subviews
    
    local endStage1P = 1/3
    
    local stage1P = math.min(percent * 3, 1)
    local stage2P = math.max(math.min((percent - endStage1P) * 3, 1), 0)
    
    for i, icon in ipairs(page.subviews) do
        local iconAngle = theta*(i-1) - math.pi/6 + stage2P*(math.pi/3)
        
        local begX = icon.x+icon.width/2
        local begY = icon.y+icon.height/2
        
        local endX = centerX+radius*math.cos(iconAngle)
        local endY = centerY-radius*math.sin(iconAngle)
        
        icon:translate((endX-begX)*stage1P, (endY-begY)*stage1P, 0)
        icon:rotate(-stage1P*((math.pi/2) + iconAngle))
    end
    
    page.alpha = 1 - stage2P
    page:translate(offset, 0, 0)
end