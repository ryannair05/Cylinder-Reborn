--[[ ******************************************************************
Explosion v1.1
by @supermamon (github.com/supermamon/cylinder-scripts/)
request by: /u/gertab

v1.1 2014-03-04: Icons father from the center move away faster.
v1.0 2014-03-04: First release.

******************************************************************* ]]

local abs, sqrt = math.abs, math.sqrt

return function(pg, of, sw, sh)

	pg:translate(of,0,0)

    local pc, cx, cy = abs(of/pg.width), pg.width/2, pg.height/2
	-- target distance
	local tg = pg.width

    for i, ic in subviews(pg) do
		-- get icon center
		local icx, icy = ic:center()
		-- get icon offset from page center
		local ox, oy = abs(cx-icx), abs(cy-icy)
		-- get hypotenuse
		local h = sqrt( ox^2+oy^2)
		-- get hypotenuse extension
		local oh = pc*tg+pc*h
		-- directions
		local dx, dy = 1,1
		if icx<cx then dx=-dx end
		if icy<cy then dy=-dy end
		if icy==cy then dy=0 end

		-- cosine and sine of the icon's angle from the page center
		local cosine, sine = 1, 0
		if h > 0 then cosine, sine = ox/h, oy/h end

		-- calc new x & y
		local nx = oh * cosine * dx
		local ny = oh * sine * dy

		-- move!!
		ic:translate(nx,ny,0)

		if pc>0.6 then
			ic.alpha = (pc-0.6)/0.4
		end

    end
end
