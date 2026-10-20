local rubik = dofile("include/rubik.lua")(dofile("include/iconCube.lua"))

-- Exactly the same as (complex), except this is personalized to my tastes. This exact same animation
-- can also be done by setting the seed in (complex) to 1394152451, iirc.

-- Each stage maps the rows or columns it turns to the direction they turn.
local layout = {
    isHorizontalFirst = true,
    first = {[1] = true, [2] = false, [4] = true},
    second = {[0] = true, [2] = false},
    third = {[0] = true, [3] = false},
}

return function(page, offset, screen_width, screen_height)
    rubik(page, offset, layout)
end
