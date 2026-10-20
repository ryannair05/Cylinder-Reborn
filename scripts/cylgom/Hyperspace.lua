-- Hyperspace animation by Cylgom

local abs, atan, pi = math.abs, math.atan, math.pi

return function(page, offset, screen_width, screen_height)
        local percent = abs(offset/page.width)
        local rollup = percent*5

        if(rollup>1) then rollup=1 end

        local front=-1
        if(offset>0) then front=1 end

        local runaway = (percent-0.2)/0.7
        if(runaway<0) then runaway=0 end
        if(runaway>1) then runaway=1 end

        local middleX =page.width/2
        local middleY =page.height/2+7
        local pitch = pi/2.4

        for i, icon in subviews(page) do
          local iconX, iconY = icon:center()

          local angle = atan((middleY-iconY)/(middleX-iconX))
          local side = 0
          if(iconX<middleX) then side = 1 end
          if(iconX>middleX) then side = -1 end
          if(abs(angle) == pi/2) then
            angle=0
            local side2 = 1
            if( middleX-iconY > 0) then
              side2 = -1
            end
            icon:rotate(rollup*pitch*(1-abs(side))*side2,1,0)
            icon:translate(0,-500*runaway*side2*front,0);
          end
          icon:rotate(rollup*angle)
          icon:rotate(rollup*pitch*side,0,1)
          icon:translate(500*runaway*side*front,0,0);
          icon.alpha = 1-runaway
        end

        page:translate(offset,0,0)
end