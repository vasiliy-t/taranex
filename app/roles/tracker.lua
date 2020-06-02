local cartridge = require("cartridge")
local fiber = require("fiber")

local errors = require("errors")
local err_httpd = errors.new_class("httpd error")
local err_config = errors.new_class("config validation error")
local ERRORS = {
    HTTPD_REQUIRED = "httpd role must be enabled",

    CFG_MUST_TABLE = "cfg.loader must be table",
    CFG_TRACKERS_MUST_TABLE = "cfg.loader.trackers must be table",

    CFG_TRACKER_MUST_TABLE = "cfg.loader.trackers.tracker must be table",
    CFG_TRACKER_MUST_SECID = "cfg.loader.trackers.secid must be string",
}

local function create_store_func()
    local icu = require("icu-date")
    local date = icu.new({zone_id='Europe/Moscow'})

    local format_date, err = icu.formats.pattern("yyyy-MM-dd HH:mm:ss")
    if err ~= nil then
        require("log").error(err)
        return nil, err
    end

    return function(v)
        local rc, err = date:parse(format_date, v[2])
        if err ~= nil then
            return nil, err
        end

        return box.space.candles:replace({
            v[1],
            date:get_millis(),
            tonumber(v[3]),
            tonumber(v[4]),
            tonumber(v[5]),
            tonumber(v[6]),
            tonumber(v[7]),
        })
    end
end

local checks = require("checks")
local function security_tracker(options)
    checks({
        secid = 'string',
        call_period = '?number',
        http_client = '?',
        store_func = '?',
    })

    local fiber = require("fiber")
    local json = require("json")
    local log = require("log")
    local http_client = require("http.client")

    local httpc = options.http_client or http_client.new()
    local store_func = options.store_func or create_store_func()
    local call_period = options.call_period or 10
    local start = 0

    repeat
        local resp = httpc:get(
            ("http://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities/%s/candles.json?start=%s&interval=1&candles.columns=begin,open,high,low,close,volume"):format(options.secid, start)
        )
        local ok, data = pcall(json.decode, resp.body)

        if data.candles ~= nil and #data.candles.data > 0 then
            for _, v in pairs(data.candles.data) do
                store_func({options.secid, unpack(v)})
            end
            start = start + #data.candles.data
            fiber.yield()
        end
        
        if data.candles == nil or #data.candles.data == 0 then 
            fiber.sleep(call_period)
        end
    until not pcall(fiber.testcancel)
end

local function init()
    local httpd = cartridge.service_get("httpd")
    if not httpd then
        return nil, err_httpd:new(HTTPD_REQUIRED)
    end

    return true
end

local function validate_config(new_cfg, old_cfg)
    local log = require("log")
    if new_cfg == nil then 
        log.warn("loader: whole config is empty")
        return true 
    end

    local loader_cfg = new_cfg.loader
    if loader_cfg == nil then
        log.warn("loader: cfg.loader section is empty")
        return true
    end

    err_config:assert(
        type(loader_cfg) == 'table',
        ERRORS.CFG_MUST_TABLE
    )

    local trackers_cfg = loader_cfg.trackers
    if trackers_cfg == nil then
        log.warn("loader: cfg.loader.trackers section is empty")
        return true
    end

    err_config:assert(
        type(trackers_cfg) == 'table',
        ERRORS.CFG_TRACKERS_MUST_TABLE
    )

    for _, v in pairs(trackers_cfg) do
        err_config:assert(
            type(v) == 'table',
            ERRORS.CFG_TRACKER_MUST_TABLE
        )

        err_config:assert(
            v['secid'] ~= nil,
            ERRORS.CFG_TRACKER_MUST_SECID
        )
    end

    return true
end

local function apply_config(cfg, opts)
    local log = require("log")
    log.info("[tracker] apply_config called")
    local fiber = require("fiber")
    local fun = require("fun")

    local cfg = cfg or {}
    local loader_cfg = cfg.loader or {}
    local trackers_cfg = loader_cfg.trackers or {}
    local fibers = fun.iter(fiber.info())

    for _, c in pairs(trackers_cfg) do
        log.info(("[tracker] attempting to create security_tracker_%s"):format(c.secid))
        local fiber_name = ("security_tracker_%s"):format(c.secid)
        local count = fibers:filter(function(_, x) return x.name == fiber_name end):reduce(function(acc, x) return acc + 1 end, 0)
        if count == 0 then 
            local f = fiber.new(security_tracker, {secid=c.secid})
            f:name(fiber_name)
        end
    end
end

local function stop()
end

return {
    init = init,
    dependencies = {
        "cartridge.roles.vshard-router"
    },
    security_tracker = security_tracker,
    store_func = create_store_func(),
    validate_config = validate_config,
    apply_config = apply_config,
    ERRORS = ERRORS,
}
