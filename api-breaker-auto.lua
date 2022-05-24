local core = require("apisix.core")
local plugin_name = "api-breaker-auto"
local ngx = ngx
local math = math
local error = error

local schema = {
    type = "object",
    properties = {
        policy = {
            type = "string",
            default = "redis",
        },
        redis_host = {
            type = "string",
            default = "127.0.0.1"
        },
        redis_port = {
            type = "integer",
            default = 6379
        },
        redis_database = {
            type = "integer",
            default = 0
        },
        break_response_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
            default = 502,
        },
        window = {
            type = "integer",
            minimum = 10,
            default = 60,
        },
        k = {
            type = "integer",
            minimum = 1,
            default = 2,
        },
        unhealthy = {
            type = "object",
            properties = {
                http_statuses = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "integer",
                        minimum = 500,
                        maximum = 599,
                    },
                    uniqueItems = true,
                    default = { 500 }
                }
            },
            default = { http_statuses = { 500 } }
        }
    },
    required = { "break_response_code" },
}

local breaker_redis_new
do
    local redis_src = "apisix.plugins.api-breaker-auto.api-breaker-auto-redis"
    breaker_redis_new = require(redis_src).new
end
local lrucache = core.lrucache.new({
    type = 'plugin', serial_creating = true,
})

local function create_breaker_obj(conf)
    core.log.info("create new api-breaker-auto plugin instance")

    if conf.policy == "redis" then
        return breaker_redis_new("plugin-" .. plugin_name, conf.window, conf)
    end

    return nil
end

local function gen_request_key(ctx)
    return "request-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function gen_accept_key(ctx)
    return "accept-" .. core.request.get_host(ctx) .. ctx.var.uri
end

local function true_on_proba(proba)
    math.randomseed(tonumber(tostring(os.time()):reverse():sub(1,6)))
    return math.random() < proba
end

local _M = {
    version = 0.1,
    name = plugin_name,
    priority = 1006,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)

    local breaker, err = core.lrucache.plugin_ctx(lrucache, ctx, conf.policy, create_breaker_obj, conf)
    if not breaker then
        core.log.error("failed to fetch api-breaker-auto object: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    local request_key = gen_request_key(ctx)
    local request_count, err = breaker:get_cnt(request_key, true)
    if err then
        core.log.warn("failed to get request_key: ",
                request_key, " err: ", err)
        return
    end

    local accept_key = gen_accept_key(ctx)
    local accept_count, err = breaker:get_cnt(accept_key, true)
    if err then
        core.log.warn("failed to get accept_key: ",
                accept_key, " err: ", err)
        return
    end

    local dr = math.max(0, (request_count - (accept_count * conf.k)) / (request_count + 1))
    local drop = true_on_proba(dr)
    if drop then
        return conf.break_response_code
    end

    return
end

function _M.log(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)

    local upstream_status = core.response.get_upstream_status(ctx)
    if not upstream_status then
        return
    end

    local breaker, err = core.lrucache.plugin_ctx(lrucache, ctx, conf.policy, create_breaker_obj, conf)
    if not breaker then
        core.log.error("failed to fetch api-breaker-auto-redis object: ", err)
        return 500
    end

    local delay = 0
    local handler
    local request_key = gen_request_key(ctx)
    local accept_key = gen_accept_key(ctx)

    handler = function (premature)
        local err = breaker:incoming(request_key, true)
        if err then
            core.log.warn("failed to `incr` request_key: ", request_key, " err: ", err)
        end

        if not core.table.array_find(conf.unhealthy.http_statuses, upstream_status)
        then
            err = breaker:incoming(accept_key, true)
            if err then
                core.log.warn("failed to incr accept_key: ", accept_key, " err: ", err)
            end
        end
    end

    local ok, err = ngx.timer.at(delay, handler)
    if not ok then
        ngx.log(ngx.ERR, "failed to create the timer: ", err)
        return
    end

    return
end

return _M
