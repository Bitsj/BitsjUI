--[[
	BitsjUI - Profile import / export
	Tables are serialized to a small text format and base64 encoded.
	The parser is hand written (no loadstring), so importing a string can
	never run code.
]]
local _, B = ...

-------------------------------------------------------------------------------
-- Serializer
-------------------------------------------------------------------------------
local function escape(s)
	return (s:gsub("[\\\"\n\r]", { ["\\"] = "\\\\", ["\""] = "\\\"", ["\n"] = "\\n", ["\r"] = "\\r" }))
end

local function serialize(v, out)
	local t = type(v)
	if t == "table" then
		out[#out + 1] = "{"
		-- sorted keys for stable output
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return a < b
		end)
		for _, k in ipairs(keys) do
			if type(k) == "number" then
				out[#out + 1] = "[" .. tostring(k) .. "]="
			else
				out[#out + 1] = "[\"" .. escape(tostring(k)) .. "\"]="
			end
			serialize(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	elseif t == "string" then
		out[#out + 1] = "\"" .. escape(v) .. "\""
	elseif t == "number" then
		out[#out + 1] = tostring(v)
	elseif t == "boolean" then
		out[#out + 1] = v and "true" or "false"
	else
		out[#out + 1] = "nil"
	end
end

function B.Serialize(v)
	local out = {}
	serialize(v, out)
	return table.concat(out)
end

-------------------------------------------------------------------------------
-- Parser
-------------------------------------------------------------------------------
local function parse(s)
	local pos = 1
	local function skip()
		pos = s:find("[^%s]", pos) or (#s + 1)
	end
	local parseValue
	local function parseString()
		pos = pos + 1 -- opening quote
		local buf = {}
		while pos <= #s do
			local c = s:sub(pos, pos)
			if c == "\\" then
				local n = s:sub(pos + 1, pos + 1)
				buf[#buf + 1] = (n == "n" and "\n") or (n == "r" and "\r") or n
				pos = pos + 2
			elseif c == "\"" then
				pos = pos + 1
				return table.concat(buf)
			else
				buf[#buf + 1] = c
				pos = pos + 1
			end
		end
		error("unterminated string")
	end
	local function parseTable()
		pos = pos + 1 -- {
		local t = {}
		while true do
			skip()
			local c = s:sub(pos, pos)
			if c == "}" then pos = pos + 1; return t end
			if c ~= "[" then error("expected [ at " .. pos) end
			pos = pos + 1
			skip()
			local key = parseValue()
			skip()
			if s:sub(pos, pos + 1) ~= "]=" then error("expected ]= at " .. pos) end
			pos = pos + 2
			skip()
			local val = parseValue()
			if key ~= nil then t[key] = val end
			skip()
			if s:sub(pos, pos) == "," then pos = pos + 1 end
		end
	end
	function parseValue()
		skip()
		local c = s:sub(pos, pos)
		if c == "{" then return parseTable()
		elseif c == "\"" then return parseString()
		elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
		elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
		elseif s:sub(pos, pos + 2) == "nil" then pos = pos + 3; return nil
		else
			local num = s:match("^-?[%d%.eE%+%-]+", pos)
			if not num then error("invalid value at " .. pos) end
			pos = pos + #num
			return tonumber(num)
		end
	end
	local v = parseValue()
	return v
end

function B.Deserialize(s)
	local ok, res = pcall(parse, s)
	if ok then return res end
	return nil, res
end

-------------------------------------------------------------------------------
-- Base64 (pure arithmetic, no bit library needed)
-------------------------------------------------------------------------------
local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap = {}
for i = 1, 64 do decodeMap[chars:sub(i, i)] = i - 1 end

function B.Base64Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = chars:sub(c1 + 1, c1 + 1) .. chars:sub(c2 + 1, c2 + 1)
			.. (b and chars:sub(c3 + 1, c3 + 1) or "=")
			.. (c and chars:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

function B.Base64Decode(data)
	data = data:gsub("[^%w%+/=]", "")
	local out = {}
	for i = 1, #data, 4 do
		local q = { data:byte(i, i + 3) }
		local n, pad = 0, 0
		for j = 1, 4 do
			local ch = q[j] and string.char(q[j]) or "="
			local v = decodeMap[ch]
			if ch == "=" or not v then v = 0; pad = pad + 1 end
			n = n * 64 + v
		end
		local a = math.floor(n / 65536) % 256
		local b = math.floor(n / 256) % 256
		local c = n % 256
		out[#out + 1] = string.char(a)
		if pad < 2 then out[#out + 1] = string.char(b) end
		if pad < 1 then out[#out + 1] = string.char(c) end
	end
	return table.concat(out)
end

-------------------------------------------------------------------------------
-- Profile strings
-------------------------------------------------------------------------------
local PREFIX = "BUI1:"

function B:ExportProfile()
	return PREFIX .. B.Base64Encode(B.Serialize(self.db))
end

-- returns ok, message
function B:ImportProfile(str, newName)
	str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if str:sub(1, #PREFIX) ~= PREFIX then
		return false, "Invalid string (missing BUI1:)"
	end
	local data, err = B.Deserialize(B.Base64Decode(str:sub(#PREFIX + 1)))
	if type(data) ~= "table" then
		return false, "Could not read the profile: " .. tostring(err)
	end
	local name = newName
	if not name or name == "" then name = self.profileKey end
	BitsjUIDB.profiles[name] = data
	self:SetProfile(name)
	return true, "Profile imported as \"" .. name .. "\""
end
