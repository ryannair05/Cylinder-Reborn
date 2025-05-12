--[[ *******************************************************
iconSpin library function v1.1
by @supermamon (github.com/supermamon/cylinder-scripts/)

Description:
	Rotates all icons

Parameters
	page	: assign to page
	percent	: percentage of transition
	tumbles : number or rotations

v1.2 2024-08-02: Optimization update for Cylinder Reborn v1.1.1 by Ryan Nair
v1.1 2014-02-16: Compatibility update for Cylinder v0.13.2.15
v1.0 2014-02-15: First Release
******************************************************** ]]
return function (page, percent, tumbles, reverse)
    local angle = percent*math.pi*2*tumbles

    local i = 0
	
	local direction = reverse and -1 or 1
    for i = 1, #page do
        page[i]:rotate(direction * angle)
    end
end