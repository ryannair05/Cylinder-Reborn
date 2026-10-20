-- Suck animation by cylgom
-- Try to combine it with Blinds
local atan = math.atan

return function(page, offset, screen_width, screen_height)
	local width = page.width
	local percent = offset/width
	local fixed = math.abs(percent)
	local side = 0
	if percent>0 then side = 1 end
	local pathX = width*side
	local bottom = page.height+7
	local size = math.sqrt(-fixed+1)
	for i, icon in subviews(page) do
		local iconX, iconY = icon:center()
		local absX  = iconX+side*(screen_width-2*iconX)
		local pathY = bottom+icon.height/2
		local iconAngle = atan(iconY/absX)
		icon:translate((pathX-iconX)*fixed, (pathY-iconY)*fixed, 0)
		icon:rotate(percent*(iconAngle))
		icon:scale(size)
	end
end