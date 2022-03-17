local _M = { version = "1.0.0" }

local function init(host, port, db)
	local host = host or os.getenv("REDIS_HOST") or "127.0.0.1"
	local port = port or tonumber(os.getenv("REDIS_PORT")) or 6379
	local db = db or tonumber(os.getenv("REDIS_DB")) or 0
	local redis = require("resty.redis")
	local red = redis:new()
	red:set_timeouts(1000, 1000, 1000) -- 1 sec
	local ok, err = red:connect(host, port)
	if ok then
		red:select(db)
		return red, nil
	end
	return nil, err
end

local function save_request_stats()
	local red, err = init()
	if red then
		red:zincrby(ngx.var.host .. ":UAS", 1, ngx.var.http_user_agent)
		red:zincrby(ngx.var.host .. ":REQ", 1, ngx.var.uri)
		local lang = ngx.var.http_accept_language
		if lang then
			red:zincrby(ngx.var.host .. ":LANG", 1, lang)
		end
		red:set_keepalive(10000, 100)
	else
		ngx.log(ngx.ERR, "error saving request stats to redis: " .. err)
	end
end

_M.init = init
_M.save_request_stats = save_request_stats
return _M
