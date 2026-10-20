-- Every icon slides straight toward the page center. This used to be done with CRAAAZY trig
-- stuff, which works out to the same thing but divides by zero for an icon at the very center.

return function(page, offset, screen_width, screen_height)
    local percent = math.abs(offset/page.width)

    local center_x = page.width/2
    local center_y = page.height/2

    for i, icon in subviews(page) do
        local x, y = icon:center()
        icon:translate(percent*(center_x - x), percent*(center_y - y), 0)
    end
end
