--[[ ******************************************************************
Ant Lines (Horizontal) v1.2
by @supermamon (github.com/supermamon/cylinder-scripts/)

Alternating Slide left/right transition.
Also works inside folders.
Compatible with iPad Landscape

v1.2 2014-03-26: Optimizations
v1.1 2014-02-16: Compatibility update for Cylinder v0.13.2.15
v1.0 2014-02-15: First Release
******************************************************************* ]]
local fade      = dofile("include/fade.lua")
local stayPut   = dofile("include/stayPut.lua")

-- MAIN --
return function(page, offset, screen_width, screen_height)

	-- track progress
	local percent = offset/page.width
	
	-- ** PAGE EFFECTS ** --
	stayPut(page,offset)
	fade(page,percent)

	-- ** ICON EFFECTS ** --
	local direction = 1 
	local lastY = 0

    for i, icon in subviews(page) do
		-- if this icon is on the next row
		if (lastY < icon.y) then 
			direction=-direction
			lastY = icon.y
		end
		icon:translate(direction*offset, 0, 0)
    end	
	
end
