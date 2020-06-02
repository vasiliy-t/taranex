#!/usr/bin/env tarantool

require('strict').on()

rawset(
    _G, 
    'to_record_batch', 
    function(acc, x)
        local n = acc:get_schema():get_fields()
        
        for i, f in ipairs(n) do
            acc:get_column_builder(i - 1):append(x[f:get_name()])
        end
        
        return acc
    end
)

rawset(
    _G,
    'new_schema',
    function(schema)
        local lgi = require("lgi")
        local Arrow = lgi.Arrow
        local m = {
            ['timestamp[ms]'] = function()
                return Arrow.TimestampDataType.new(Arrow.TimeUnit.MILLI)
            end,
            ['float'] = function() 
                return Arrow.FloatDataType.new()
            end,
            ['string'] = function()
                return Arrow.StringDataType.new()
            end
        }
        local fields = {}
        for _, t in ipairs(schema) do
            table.insert(fields, Arrow.Field.new(t.name, m[t.type]()))
        end

        return Arrow.RecordBatchBuilder.new(Arrow.Schema.new(fields))
    end
)

if package.setsearchroot ~= nil then
    package.setsearchroot()
else
    -- Workaround for rocks loading in tarantool 1.10
    -- It can be removed in tarantool > 2.2
    -- By default, when you do require('mymodule'), tarantool looks into
    -- the current working directory and whatever is specified in
    -- package.path and package.cpath. If you run your app while in the
    -- root directory of that app, everything goes fine, but if you try to
    -- start your app with "tarantool myapp/init.lua", it will fail to load
    -- its modules, and modules from myapp/.rocks.
    local fio = require('fio')
    local app_dir = fio.abspath(fio.dirname(arg[0]))
    print('App dir set to ' .. app_dir)
    package.path = package.path .. ';' .. app_dir .. '/?.lua'
    package.path = package.path .. ';' .. app_dir .. '/?/init.lua'
    package.path = package.path .. ';' .. app_dir .. '/.rocks/share/tarantool/?.lua'
    package.path = package.path .. ';' .. app_dir .. '/.rocks/share/tarantool/?/init.lua'
    package.cpath = package.cpath .. ';' .. app_dir .. '/?.so'
    package.cpath = package.cpath .. ';' .. app_dir .. '/?.dylib'
    package.cpath = package.cpath .. ';' .. app_dir .. '/.rocks/lib/tarantool/?.so'
    package.cpath = package.cpath .. ';' .. app_dir .. '/.rocks/lib/tarantool/?.dylib'
end

local cartridge = require('cartridge')
local ok, err = cartridge.cfg({
    workdir = 'tmp/db',
    roles = {
        'cartridge.roles.vshard-storage',
        'cartridge.roles.vshard-router',
        'app.roles.storage',
        'app.roles.tracker',
        'grafana-tarantool-datasource-backend.grafana_backend',
    },
    cluster_cookie = 'taranex-cluster-cookie',
})

assert(ok, tostring(err))
