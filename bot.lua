do
	local appendDataInFile = function(fileName, data, writeType)
		fileName = io.open(fileName, (writeType or "a+"))
		fileName:write("\n" .. data)
		fileName:flush()
		fileName:close()
	end

	local output = print
	print = function(...)
		local data = table.concat({ ... }, "\t")
		data, breakLines = string.gsub(data, "^\n+", '')

		appendDataInFile("logs.log", string.rep("\n", breakLines) .. os.date("[%x %X] ") .. data)

		return output(...)
	end

	appendDataInFile("logs.log", '', "w+") -- Clear
end

local authkeys = require("authkeys")
local extensions = require("extensions")

local fromage = require("fromage")
local client = fromage()

local teams = {
	["amaterasu"]                  = { score = 0 },
	["b e a r s"]                  = { score = 0 },
	["blink"]                      = { score = 0 },
	["capa amarela"]               = { score = 0 },
	["camundongos unidos"]         = { score = 0 },
	["chámantes"]                  = { score = 0 },
	["clube das winx"]             = { score = 0 },
	["fast mouse"]                 = { score = 0 },
	["first blooders invencibles"] = { score = 0 },
	["framengo"]                   = { score = 0 },
	["free win"]                   = { score = 0 },
	["helpers br"]                 = { score = 0 },
	["lindos e gostosos"]          = { score = 0 },
	["lute como uma garota"]       = { score = 0 },
	["masterchefs"]                = { score = 0 },
	["nightmare"]                  = { score = 0 },
	["nukenins"]                   = { score = 0 },
	["prisma vault"]               = { score = 0 },
	["ragers"]                     = { score = 0 },
	["rank's speed"]               = { score = 0 },
	["squad godness"]              = { score = 0 },
	["utility 45"]                 = { score = 0 },
	["viciados na vanilla"]        = { score = 0 },
	["zimzalabim"]                 = { score = 0 }
}
local unknownAllies, skippedMessages = { }, { }
local cachedVotes = { }

local start = function()
	client.connect(authkeys.LOGIN, authkeys.PASSWORD)

	if not client.isConnected() then
		print("Failed to start. Trying to connect...")
		return false
	end
	return true
end

local getScore
do
	getScore = function(nickname)
		local num = { string.match(nickname, "#((%d)(%d)(%d)(%d))$") }
		local discriminator = tonumber(table.remove(num, 1))

		if discriminator == 0 then
			return 0
		end

		-- str -> int
		for n = 1, 4 do
			num[n] = tonumber(num[n])
		end

		-- 0095
		if discriminator == 95 then
			return 2, "ex-staff"
		end

		-- Equal (ex: #6666)
		if (num[1] == num[2]
			and num[2] == num[3]
			and num[3] == num[4]) then
			return 3, "equal"
		end

		-- Consecutive (ex: #4567, #7654)
		for signal = -1, 1, 2 do
			if ((num[1] + signal == num[2]) and
				(num[2] + signal == num[3]) and
				(num[3] + signal == num[4])) then
				return 3, "consecutive"
			end
		end

		-- Multiple of 1000 (ex: #5000)
		if discriminator % 1000 == 0 then
			return 2, "multiple 1000"
		end

		-- Multiple of 100 (ex: 5500)
		if discriminator % 100 == 0 then
			return 1, "multiple 100"
		end

		-- Sum equals to 21 (ex: #9921)
		if (num[1] + num[2] + num[3] + num[4]) == 21 then
			return 1, "sum 21"
		end

		return 0
	end

	-- Testing getScore
	-- 0000
	assert(getScore("#0000") == 0)

	-- 0095
	assert(getScore("#0095") == 2)
	assert(getScore("#0059") == 0)

	-- Equal
	assert(getScore("#1111") == 3)
	assert(getScore("#6666") == 3)
	assert(getScore("#9999") == 3)

	-- Consecutive +1
	assert(getScore("#0123") == 3)
	assert(getScore("#4567") == 3)
	assert(getScore("#8910") == 0)
	-- Consecutive -1
	assert(getScore("#3210") == 3)
	assert(getScore("#7654") == 3)
	assert(getScore("#0198") == 0)

	-- Multiple of 1000
	assert(getScore("#1000") == 2)
	assert(getScore("#2200") == 1)
	assert(getScore("#6890") == 0)

	-- Multiple of 100
	assert(getScore("#0100") == 1)
	assert(getScore("#1100") == 1)
	assert(getScore("#6600") == 1)
	assert(getScore("#6660") == 0)

	-- Sum equals to 21
	assert(getScore("#9921") == 1)
	assert(getScore("#2134") == 0)
	assert(getScore("#6663") == 1)
	assert(getScore("#4812") == 0)
end

local validRegistrationDate = function(playerName)
	local tries, profile = 0
	repeat
		tries = tries + 1
		profile = client.getProfile(playerName)

		if tries == 5 then
			print("Could not load '" .. playerName .. "''s profile.")
			return
		end
	until profile

	local day, month, year = string.match(profile.registrationDate, "^(%d+)/(%d+)/(%d+)$")
	day, month, year = tonumber(day), tonumber(month), tonumber(year)

	if (year < 2020 or month < 4) or (month == 4 and day < 6) then
		return true
	end

	print("Invalid registration date for '" .. playerName .. "': " .. profile.registrationDate)
	return
end

local transformBbcode = function(bbcode)
	bbcode = string.gsub(bbcode, "%b[]", '') -- Remove attributes
	bbcode = string.lower(bbcode)
	-- Transform HTML characters into ASCII
	bbcode = string.gsub(bbcode, "&#(%d+);", string.char)
	bbcode = string.gsub(bbcode, "&gt;", '>')
	bbcode = string.gsub(bbcode, "&lt;", '<')
	bbcode = string.gsub(bbcode, "&quot;", '&')

	return bbcode
end

local extractTeam = function(bbcode, author, formatBbcode)
	if not bbcode then return end

	local reason
	if not string.find(bbcode, "[quote]", 1, true) then
		bbcode = transformBbcode(bbcode)

		local _, equipePos = string.find(bbcode, " equipe +")
		if equipePos
			and (string.find(bbcode, "eu me ", 1, true)
			or string.find(bbcode, " ali[oe]i? ")) then

			-- Most of them put the name after equipe. Also ignores other lines.
			local nextBreakLine = string.find(bbcode, "\n", 1, true)
			bbcode = string.sub(bbcode, equipePos + 1, (nextBreakLine and nextBreakLine - 1))

			local similarName, similarityPercentage = false, 0
			local tmpHasSimilarity, tmpSimilarityPercentage

			for name in next, teams do
				tmpHasSimilarity, tmpSimilarityPercentage = extensions.isSimilar(bbcode, name)
				if tmpHasSimilarity and tmpSimilarityPercentage > similarityPercentage then
					similarName, similarityPercentage = name, tmpSimilarityPercentage
				end
			end

			if similarName then
				print("\t" .. formatBbcode .. " is similar to '"
					.. similarName .. "' (" .. extensions.round(similarityPercentage) .. "%)")
				return similarName
			else
				unknownAllies[#unknownAllies + 1] = formatBbcode
				print("\tCould not detect team for " .. formatBbcode)
				return
			end
		else
			reason = "[no 'equipe+(eu_me|alio|aliei)' word]"
		end
	else
		reason = "[has quote]"
	end

	skippedMessages[#skippedMessages + 1] = formatBbcode
	print("\tSkipped message " .. reason .. " from " .. formatBbcode)
	return
end

local validMessageDate
do
	local GMT_3 = 60 * 60 * 3
	local transformTimestamp = function(time)
		return time and ((time / 1000) - GMT_3)
	end

	local limitDate = os.time({
		year = 2020,
		month = 4,
		day = 7,
		hour = 23,
		min = 59,
		sec = 59
	})

	validMessageDate = function(timestamp, editionTimestamp, formatBbcode)
		timestamp = transformTimestamp(timestamp)
		editionTimestamp = transformTimestamp(editionTimestamp)

		formatBbcode = transformBbcode(formatBbcode)

		if editionTimestamp then
			if editionTimestamp > limitDate then
				print("\tMessage skipped due to editionDate>limitDate " .. formatBbcode)
				return
			end
		end

		if timestamp > limitDate then
			print("\tMessage skipped due to date>limitDate " .. formatBbcode)
			return
		end

		return true, formatBbcode
	end
end

local filter = function(messages)
	local score
	local scoreType -- metric only
	local teamName
	local formatBbcode -- aux tmp
	local hasValidMessageDate

	for m = 1, #messages do
		m = messages[m]
		if m and m.content and not cachedVotes[m.author] then
			score, scoreType = getScore(m.author) -- Only gets, but does not sum (yet)
			if score > 0 then
				formatBbcode = "'" .. m.author .. "': " .. string.format("%q", m.content)

				hasValidMessageDate, formatBbcode =
					validMessageDate(m.timestamp, m.editionTimestamp, formatBbcode)

				if hasValidMessageDate then
					teamName = extractTeam(m.content, m.author, formatBbcode)
					if teamName then
						cachedVotes[m.author] = true

						if true or validRegistrationDate(m.author) then
							teamName = teams[teamName]
							teamName.score = teamName.score + score

							if not teamName[scoreType] then
								teamName[scoreType] = 1
							else
								teamName[scoreType] = teamName[scoreType] + 1
							end
						end
					end
				end
			end
		end
	end
end

local printScore = function()
	-- Sort teams by score
	local sortedTbl, index = { }, 0
	for k, v in next, teams do
		index = index + 1
		sortedTbl[index] = { k, v }
	end
	table.sort(sortedTbl, function(a, b)
		return a[2].score > b[2].score
	end)

	-- Sort names by alpha
	local allies, namesIndex = { }, 0
	for k, v in next, cachedVotes do
		namesIndex = namesIndex + 1
		allies[namesIndex] = k
	end
	table.sort(allies, function(a, b)
		return b > a
	end)
	allies = table.concat(allies, " - ")

	-- Display
	for data = 1, index do
		data = sortedTbl[data]

		if data[2].score > 0 then
			print("\n" .. data[1] .. " - " .. data[2].score .. " points")
			for scoreType, qty in next, data[2] do
				if scoreType ~= "score" then
					print("\t" .. scoreType .. ": " .. qty)
				end
			end
		end
	end

	local lenUnknownAllies = #unknownAllies
	print("\n\nUnknown allies: " .. lenUnknownAllies)
	for i = 1, lenUnknownAllies do
		print("\t" .. string.format("%q", unknownAllies[i]))
	end

	local lenSkippedMessages = #skippedMessages
	print("\n\nSkipped messages: " .. lenSkippedMessages)
	for i = 1, lenSkippedMessages do
		print("\t" .. string.format("%q", skippedMessages[i]))
	end

	print("\n\nAll allies: " .. allies)
end

coroutine.wrap(function()
	print("Connecting...")
	repeat until start()

	-- Gets all messages from page N to 7
	local messages
	for page = 25, 7, -1 do
		print("\nGetting page " .. page)
		messages = client.getAllMessages({ f = 5, t = 924758 }, true, page)
		print("Got page " .. page)

		filter(messages)
	end

	printScore()

	client.disconnect()
	print("\nFinished")
	os.execute("pause >nul")
end)()