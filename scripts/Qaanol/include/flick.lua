local max, sin, pi = math.max, math.sin, math.pi

return function(page, offset, flips, spread, endFlips, endSpeed, advancing, spinAtStart, tiltAngle)
    -- Defaults for optional parameters
    flips = flips or 1                      -- Number of half-turns to spin icons
    spread = spread or 1                    -- How far apart icons begin to spin
    endFlips = endFlips or flips            -- Half-turns of last icon
    endSpeed = endSpeed or 1                -- Relative speed of final icon spin
    tiltAngle = tiltAngle or pi / 10        -- Maximum perspective angle during spin

    local pageWidth = page.width
    local p = (offset/pageWidth) % 1
    local isLeft = offset < 0
    local endTime = endFlips / endSpeed
    local scale = spread + max(flips, endTime)
    -- An unresolved grid reports zero columns, which would divide by zero.
    local gap = pageWidth / max(page.max_columns, 1)
    local halfGap = 0.5 * gap
    local width = pageWidth - gap
    local t = p * scale
    local endsAtRight = advancing == spinAtStart

    for i, icon in subviews(page) do
        -- Icon-specific animation timeline
        local x = icon.layer.x
        local position = (x - halfGap) / width
        local flipCount = flips
        local flipTime = flips

        if endsAtRight then
            if x > width then
                flipCount = endFlips
                flipTime = endTime
            end
        else
            if x < gap then
                flipCount = endFlips
                flipTime = endTime
            end
        end

        local start = (1 - position) * spread
        local stop = start + flipTime

        if endsAtRight then
            stop = scale - (spread - start)
            start = stop - flipTime
        end

        -- Every icon is visible unless its back face or its finished spin hides it
        local alpha = 1

        if t < start then
            if isLeft then alpha = 0 end
        elseif t > stop then
            if not isLeft then alpha = 0 end
        else
            -- Animation progress
            local frac = (t - start) / (stop - start)
            local a = -flipCount * frac

            -- Set visible side of spinning icon
            if isLeft then
                if ((a - 0.5) % 2) > 1 then
                    alpha = 0
                else
                    -- Orient the back face correctly
                    a = a + 1
                end
            else
                if ((a - 0.5) % 2) < 1 then alpha = 0 end
            end

            -- Smoothly tilt to perspective during spin
            local tilt = tiltAngle * sin(pi * frac)

            icon:rotate(-tilt, 1, 0, 0)
            icon:rotate(a * pi, 0, 1, 0)
        end

        icon.alpha = alpha
    end
end
