--[[ *******************************************************
Alternate Spin v1.2
by @supermamon (github.com/supermamon/cylinder-scripts/)

A modification of the built-in Spin effect.
This reverses the spin direction of every other icon

v1.2 2014-03-26: Optimizations
v1.1 2014-02-16: Code enhancements
v1.0 2014-02-13: First Release
******************************************************** ]]
return function(page, offset, screen_width, screen_height)
    local percent = offset/page.width
	local tumbles = 1 
    local angle = percent*math.pi*2*tumbles

    for i, icon in subviews(page) do
		angle = -angle --reverse for each one
        icon:rotate(angle)
    end
end
