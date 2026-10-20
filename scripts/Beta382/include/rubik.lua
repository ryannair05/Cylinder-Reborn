-- Shared by the Rubik's Cube scripts. A layout lists which rows or columns turn in each of three
-- stages, as sets that map each row or column to the direction it turns:
--   { isHorizontalFirst = true, first = {[1] = true}, second = {[0] = false}, third = {[2] = true} }
-- With isHorizontalFirst, the first and third stages turn rows and the second turns columns.

-- A value from 0 to 1/3 that specifies how long each row should take to complete animating
-- Change this and only this, hackers. If you make it larger than 1/3, weird things will happen.
-- Although, that might be exactly what you want, so I'm not doing any bounds checking. Hack away
local animationDuration = 1/3

local magic = (1-animationDuration)/2 -- Adapted from another script. Literally is magic
local speed = 1/animationDuration

local function clamp(value, low, high)
    if value > high then return high end
    if value < low then return low end
    return value
end

return function(iconCube)
    return function(page, offset, layout)
        local percent = offset/page.width
        local forwards = offset >= 0

        local stage1P, stage2P, stage3P
        if forwards then
            stage1P = clamp(percent*speed, 0, 1)
            stage2P = clamp((percent-magic)*speed, 0, 1)
            stage3P = clamp((percent-2*magic)*speed, 0, 1)
        else
            stage1P = clamp((percent+2*magic)*speed, -1, 0)
            stage2P = clamp((percent+magic)*speed, -1, 0)
            stage3P = clamp(percent*speed, -1, 0)
        end

        local isHorizontalFirst = layout.isHorizontalFirst
        local first, second, third = layout.first, layout.second, layout.third

        for i, icon in subviews(page) do
            -- `outer` is the axis the first and third stages turn, `inner` the one the second turns.
            local outer, inner
            if isHorizontalFirst then
                outer, inner = icon.row, icon.column
            else
                outer, inner = icon.column, icon.row
            end

            local firstDir, secondDir, thirdDir = first[outer], second[inner], third[outer]

            if firstDir ~= nil and not (secondDir ~= nil and not forwards) then
                iconCube(page, icon, stage1P, isHorizontalFirst, firstDir)
            end

            if secondDir ~= nil and not (thirdDir ~= nil and not forwards)
                                and not (firstDir ~= nil and forwards) then
                iconCube(page, icon, stage2P, not isHorizontalFirst, secondDir)
            end

            if thirdDir ~= nil and not (secondDir ~= nil and forwards) then
                iconCube(page, icon, stage3P, isHorizontalFirst, thirdDir)
            end
        end

        page:translate(offset, 0, 0)
    end
end
