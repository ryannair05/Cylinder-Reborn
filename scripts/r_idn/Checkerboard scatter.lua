local function scatter(view, percent, height)
    for i, v in ipairs(view) do
        local mult = (i % 2 == 0) and -1 or 1
        v:translate(0, mult * percent * height, 0)
    end
end

return function(page, offset, screen_width, screen_height)
    local percent = math.abs(offset/page.width)
    scatter(page, percent, page.height / 2)
end

