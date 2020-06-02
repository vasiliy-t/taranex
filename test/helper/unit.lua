local t = require('luatest')

local shared = require('test.helper')

local helper = {shared = shared}

t.before_suite(function() 
    package.path = package.path .. ';' .. shared.root .. '/?.lua'
    box.cfg({work_dir = shared.datadir}) 
end)

return helper
