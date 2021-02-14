return function(page, offset, screen_width, screen_height)
    local percent = math.abs(offset/page.width)
    
    local centerX = page.width/2
    local centerY = page.height/2+7
    local radius = 0.30*page.width
    if radius > page.height then radius = 0.30*page.height end
    
    local theta = (2*math.pi)/#page.subviews
    
    local stage1P = percent*2
    if (stage1P > 1) then stage1P = 1 end
    
    local stage2P = (percent-1/2)*2
    if (stage2P > 1) then stage2P = 1
    elseif (stage2P < 0) then stage2P = 0 end
    
    for i, icon in subviews(page) do
        local iconAngle = theta*(i-1)+stage2P*(math.pi/2)
        
        local begX = icon.x+icon.width/2
        local begY = icon.y+icon.height/2
        
        local endX = centerX+radius*math.cos(iconAngle)
        local endY = centerY-radius*math.sin(iconAngle)
        
        icon:translate((endX-begX)*stage1P, (endY-begY)*stage1P, 0)
        icon:rotate(-stage1P*((math.pi/2) + iconAngle))
    end
end