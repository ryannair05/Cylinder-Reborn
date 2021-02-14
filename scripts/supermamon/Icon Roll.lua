--[[ ******************************************************************
Icon Roll v1.1
by @supermamon (github.com/supermamon/cylinder-scripts/)

Same as Spin. In reversed direction. Requested by /u/Sapharodon

v1.1 2014-03-26: Use iconSpin library.
v1.0 2014-03-26: First release.
******************************************************************* ]]
local iconSpin   = dofile("include/iconSpin.lua")
return function(page, offset, screen_width, screen_height)
   local percent = offset/page.width
   iconSpin(page,percent,1,true)
end