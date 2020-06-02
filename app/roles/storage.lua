local function init(opts)
    if opts.is_master then
        box.schema.space.create("candles", {if_not_exists = true})
        box.space.candles:format(
            {
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
    end

    return true
end

return {
    init = init,
    dependencies = {
        "cartridge.roles.vshard-storage"
    }
}
