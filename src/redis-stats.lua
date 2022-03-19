local _M = { version = "1.0.0" }
local redis = require("resty.redis")
local uuid = require("resty.jit-uuid")

local function init(host, port, db)
	local host = host or os.getenv("REDIS_HOST") or "127.0.0.1"
	local port = port or tonumber(os.getenv("REDIS_PORT")) or 6379
	local db = db or tonumber(os.getenv("REDIS_DB")) or 0
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

local function mark_page_view(suffix, page_uuid)
	local suffix = suffix or ":page_view_hashes:"
	local page_uuid = page_uuid or uuid()
	local red, err = init()
	if red then
		red:sadd(ngx.var.host .. suffix .. ngx.var.uri, page_uuid)
		if ngx.status and ngx.status >= 400 then
			red:zincrby(ngx.var.host .. ":" .. tostring(ngx.status), 1, ngx.var.uri)
		end
		red:set_keepalive(10000, 100)
	end
	return page_uuid, ngx.encode_base64(ngx.var.uri, true)
end

local function confirm_page_view(suffix)
	local suffix = suffix or { ":page_view_hashes:", ":page_views" }
	if ngx.var.arg_p and ngx.var.arg_h then
		local red = init()
		if red then
			local count = red:srem(ngx.var.host .. suffix[1] .. ngx.decode_base64(ngx.var.arg_p), ngx.var.arg_h)
			if count and count == 1 then
				red:zincrby(ngx.var.host .. suffix[2], 1, ngx.decode_base64(ngx.var.arg_p))
			end
			red:set_keepalive(10000, 100)
		end
	end
end

local function get_page_views(suffix)
	local suffix = suffix or ":page_views"
	local red = init()
	local count = 0
	if red then
		local c = red:zscore(ngx.var.host .. suffix, ngx.var.uri)
		red:set_keepalive(10000, 100)
		if c then
			if c ~= ngx.null then
				count = c
			end
		end
	end
	return count
end

_M.init = init
_M.save_request_stats = save_request_stats
_M.mark_page_view = mark_page_view
_M.confirm_page_view = confirm_page_view
_M.get_page_views = get_page_views
return _M
