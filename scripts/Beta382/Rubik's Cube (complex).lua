local rubik = dofile("include/rubik.lua")(dofile("include/iconCube.lua"))
local random, floor, ceil = math.random, math.floor, math.ceil

 -- This is updated every time you select this effect. You can set it manually if
 -- you find a seed you really like, and want it to /always/ look like that.
local seed = os.time()

 -- Uncomment the line below to plant the seed in /var/mobile/Library/Logs/Cylinder/print.log
 -- Do so if you want to find which seed you like
--print (seed)

--cool seeds: 1394149256, 1394152451

-- Picks `count` different rows or columns below `limit`, each with a random direction.
local function pick(count, limit, values, directions)
    local taken = {}
    for i=1, count do
        local value = random(0, limit-1)
        while taken[value] do
            value = random(0, limit-1)
        end
        taken[value] = true
        values[i] = value
        directions[i] = random(0,1) == 1
    end
end

-- Turns parallel lists of rows or columns and directions into a set keyed by row or column.
local function stageSet(values, directions, from, to)
    local set = {}
    for i=from, to do set[values[i]] = directions[i] end
    return set
end

-- Builds the layout for a grid size. Every page of that size shares it, so it is built once.
local function makeLayout(maxRows, maxColumns)
    math.randomseed(seed)

    local isHorizontalFirst = random(0,1) == 1

    -- Stage 1 turns every line along the first axis; the lines after `numToSet` move to stage 3.
    local outerCount = isHorizontalFirst and maxRows or maxColumns
    local innerCount = isHorizontalFirst and maxColumns or maxRows

    local outer, outerDir = {}, {}
    local numToSet = random(floor(outerCount/2), ceil(outerCount/2))
    pick(outerCount, outerCount, outer, outerDir)

    local inner, innerDir = {}, {}
    pick(random(floor(innerCount/2), ceil(innerCount/2)), innerCount, inner, innerDir)

    return {
        isHorizontalFirst = isHorizontalFirst,
        first = stageSet(outer, outerDir, 1, numToSet),
        second = stageSet(inner, innerDir, 1, #inner),
        third = stageSet(outer, outerDir, numToSet+1, outerCount),
    }
end

local layouts = {}

return function(page, offset, screen_width, screen_height)
    local maxRows, maxColumns = page.max_rows, page.max_columns
    local key = maxRows*4096 + maxColumns
    local layout = layouts[key]
    if not layout then
        layout = makeLayout(maxRows, maxColumns)
        layouts[key] = layout
    end
    rubik(page, offset, layout)
end
