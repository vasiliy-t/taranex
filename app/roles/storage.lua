local function candles_replace(data)
  return box.space.candles:replace(data)
end

local function init(opts)
    if opts.is_master then
        box.schema.space.create("candles", {if_not_exists = true})
        box.space.candles:format(
            {
                {name = "bucket_id", type = "unsigned"},
                {name = "secid", type = "string"},
                {name = "begin", type = "number"},
                {name = "open", type = "number"},
                {name = "high", type = "number"},
                {name = "low", type = "number"},
                {name = "close", type = "number"},
                {name = "volume", type = "number"}
            }
        )
        box.space.candles:create_index("pk", {parts = {"secid", "begin"}, if_not_exists = true})
        box.space.candles:create_index("bucket_id", {parts = {"bucket_id"}, unique = false, if_not_exists = true})

        rawset(_G, "candles_replace", candles_replace)
    end

    return true
end

return {
    init = init,
    candles_replace = candles_replace,
    dependencies = {
        "cartridge.roles.vshard-storage"
    }
}
