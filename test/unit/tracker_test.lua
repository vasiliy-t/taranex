local t = require("luatest")
local g = t.group("tracker_test")
local app_roles_tracker = require("app.roles.tracker")

require("test.helper.unit")

t.assert_throws = function(expected_err, func, ...)
    local ok, err = pcall(func, ...)

    t.assert_type(err, 'table', ("error must be table %s given"):format(type(err)))
    t.assert_type(err.err, 'string', ("error message must be string %s given"):format(type(err.err)))
    t.assert_str_contains(err.err, expected_err, ("must throw %s error"):format(expected_err))
end

local validate_config = t.group("validate_config")
validate_config.test_empty_config_passes = function()
    t.assert_equals(app_roles_tracker.validate_config({}, {}), true)
    t.assert_equals(app_roles_tracker.validate_config({loader = nil}, {}), true)
    t.assert_equals(app_roles_tracker.validate_config({loader = {}}, {}), true)
end

validate_config.test_invalid_cfg_type_throws = function()
    t.assert_throws(app_roles_tracker.ERRORS.CFG_MUST_TABLE, app_roles_tracker.validate_config, {loader=1}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_MUST_TABLE, app_roles_tracker.validate_config, {loader="loader config"}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_MUST_TABLE, app_roles_tracker.validate_config, {loader=true}, {})
end

validate_config.test_empty_trackers_passes = function()
    t.assert_equals(app_roles_tracker.validate_config({loader={trackers=nil}}, {}), true)
    t.assert_equals(app_roles_tracker.validate_config({loader={trackers={}}}, {}), true)
end

validate_config.test_invalid_trackers_throws = function()
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKERS_MUST_TABLE, app_roles_tracker.validate_config, {loader={trackers=1}}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKERS_MUST_TABLE, app_roles_tracker.validate_config, {loader={trackers='string'}}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKERS_MUST_TABLE, app_roles_tracker.validate_config, {loader={trackers=true}}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKERS_MUST_TABLE, app_roles_tracker.validate_config, {loader={trackers=0x1}}, {})
end

validate_config.test_invalid_tracker_throws = function()
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKER_MUST_TABLE, app_roles_tracker.validate_config, {loader={trackers={1, 'str'}}}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKER_MUST_SECID, app_roles_tracker.validate_config, {loader={trackers={{}}}}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKER_MUST_SECID, app_roles_tracker.validate_config, {loader={trackers={{field=1}}}}, {})
    t.assert_throws(app_roles_tracker.ERRORS.CFG_TRACKER_MUST_SECID, app_roles_tracker.validate_config, {loader={trackers={{['sec_id']=1}}}}, {})
end

local apply_config = t.group("apply_config")
apply_config.test_empty_config_not_fails = function()
    t.assert_is(app_roles_tracker.apply_config(nil, nil), nil)
    t.assert_is(app_roles_tracker.apply_config({}, nil), nil)
    t.assert_is(app_roles_tracker.apply_config({loader=nil}, nil), nil)
    t.assert_is(app_roles_tracker.apply_config({loader={}}, nil), nil)
end

apply_config.test_creates_tracker_fibers = function()
    local fiber = require("fiber")
    local fun = require("fun")

    app_roles_tracker.apply_config({loader={trackers={{["secid"] = "MTSS"}}}})
    local info = fiber.info()
    local f = fun.iter(fiber.info()):filter(function(_, x) return x.name == 'security_tracker_MTSS' end):totable()
    t.assert_equals(#f, 1)
end

local security_tracker = t.group("security_tracker")
security_tracker.test_loads_expected_security = function() 
    local fiber = require("fiber")
    local json = require("json")
    local req_count = 0
    local sec_ids = {
        ["MTSS"] = false,
        ["YNDX"] = false
    }

    local store_func = function(tuple)
        req_count = req_count + 1
        return
    end

    local mock_httpc = {
        get = function(_, uri)
            if uri == "http://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities/MTSS/candles.json?start=0&interval=1&candles.columns=begin,open,high,low,close,volume" then
                sec_ids["MTSS"] = true
                return {
                    body = json.encode(
                        {
                            candles = {
                                data = {
                                    {"2014-06-04 10:04:00", 1546.7, 1546.7, 1546.7, 1546.7, 1},
                                }
                            }
                        }
                    )
                }
            end

            if uri == "http://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities/YNDX/candles.json?start=0&interval=1&candles.columns=begin,open,high,low,close,volume" then
                sec_ids["YNDX"] = true
                return {
                    body = json.encode(
                        {
                            candles = {
                                data = {{"2014-06-04 10:04:00", 1546.7, 1546.7, 1546.7, 1546.7, 1}}
                            }
                        }
                    )
                }
            end

            return {
                body = json.encode(
                    {
                        candles = {
                            data = {}
                        }
                    }
                )
            }
        end
    }

    fiber.new(app_roles_tracker.security_tracker, {secid="MTSS", http_client=mock_httpc, store_func=store_func})
    fiber.new(app_roles_tracker.security_tracker, {secid="YNDX", http_client=mock_httpc, store_func=store_func})
    fiber.yield()

    for id, hit in pairs(sec_ids) do
        t.assert_equals(hit, true, id)
    end
end

security_tracker.test_loads_secs = function()
    local fiber = require("fiber")
    local json = require("json")
    local req_count = 0

    local store_func = function(tuple)
        req_count = req_count + 1
        return
    end

    local mock_httpc = {
        get = function(_, uri)
            if uri == "http://iss.moex.com/iss/engines/stock/markets/shares/boards/TQBR/securities/MTSS/candles.json?start=0&interval=1&candles.columns=begin,open,high,low,close,volume" then
                return {
                    body = json.encode(
                        {
                            candles = {
                                data = {
                                    {"2014-06-04 10:04:00", 1546.7, 1546.7, 1546.7, 1546.7, 1},
                                    {"2014-06-04 10:04:00", 1546.7, 1546.7, 1546.7, 1546.7, 1}
                                }
                            }
                        }
                    )
                }
            end

            return {
                body = json.encode(
                    {
                        candles = {
                            data = {}
                        }
                    }
                )
            }
        end
    }

    fiber.new(app_roles_tracker.security_tracker, {secid="MTSS", http_client=mock_httpc, store_func=store_func})
    fiber.yield()

    t.assert_equals(req_count, 2)
end

security_tracker.test_retries_on_response_decode_failure = function()
    local fiber = require("fiber")
    local json = require("json")
    local call_count = 0

    local mock_httpc = {
        get = function(_, uri)
            call_count = call_count + 1
            return {
                body = "invalid json"
            }
        end
    }

    fiber.new(app_roles_tracker.security_tracker, {secid="MTSS", call_period=1, http_client=mock_httpc, store_func=function() end})
    fiber.sleep(3)

    t.assert_equals(call_count >= 2, true)
end
