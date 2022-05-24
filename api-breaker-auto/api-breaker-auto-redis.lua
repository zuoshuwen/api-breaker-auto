local redis_new = require("resty.redis").new
local core = require("apisix.core")
local assert = assert
local setmetatable = setmetatable
local tostring = tostring
local ngx        = ngx
local ngx_now  = ngx.now


local _M = {version = 0.1}


local mt = {
    __index = _M
}


local script_rec = core.string.compress_script([=[
    if redis.call('ZADD', KEYS[1], ARGV[1], ARGV[2]) then
		return redis.call('EXPIRE', KEYS[1], ARGV[3])
	end
	return -1
]=])


local script_cnt = core.string.compress_script([=[
	if redis.call('ttl', KEYS[1]) < 0 then
        return 0
    end

	redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, ARGV[2]-1)

	local count = 0
	for _ in pairs(redis.call('ZREVRANGEBYSCORE', KEYS[1], ARGV[1], ARGV[2])) do count = count + 1 end
	return count
]=])

function _M.new(plugin_name, window, conf)
    local self = {
        window = window,
        conf = conf,
        plugin_name = plugin_name,
    }
    return setmetatable(self, mt)
end

local function get_redis(conf, key)
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000
    core.log.info("ttl key: ", key, " timeout: ", timeout)

    red:set_timeouts(timeout, timeout, timeout)

    local ok, err = red:connect(conf.redis_host, conf.redis_port or 6379)
    if not ok then
        return false, err
    end

    local count
    count, err = red:get_reused_times()
    if 0 == count then
        if conf.redis_password and conf.redis_password ~= '' then
            local ok, err = red:auth(conf.redis_password)
            if not ok then
                return false, err
            end
        end

        if conf.redis_database ~= 0 then
            local ok, err = red:select(conf.redis_database)
            if not ok then
                return false, "failed to change redis db, err: " .. err
            end
        end
    elseif err then
        return false, err
    end

    return red, nil
end

function _M.incoming(self, key)
    local conf = self.conf
    local red, err = get_redis(conf, key)
    if err then
        return err
    end

    local window = self.window
    local ret
    key = self.plugin_name .. tostring(key)

    ret, err = red:eval(script_rec, 1, key, ngx_now(), ngx_now(), window)

    if err then
        return err
    end

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        return err
    end

    if ret < 0 then
        return "rejected"
    end

    return nil
end

function _M.get_cnt(self, key)
    local conf = self.conf
    local red, err = get_redis(conf, key)
    if err then
        return nil, err
    end

    local window = self.window
    local cnt
    key = self.plugin_name .. tostring(key)

    cnt, err = red:eval(script_cnt, 1, key, ngx_now(), ngx_now() - (window * 1000))

    if err then
        return nil, err
    end

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        return nil, err
    end

    if cnt < 0 then
        return nil, "rejected"
    end
    return cnt, nil
end

return _M