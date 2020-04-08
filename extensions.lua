local levenshtein = function(str1, str2)
	if str1 == str2 then return 0 end

	local len1 = #str1
	local len2 = #str2

	if len1 == 0 then
		return len2
	elseif len2 == 0 then
		return len1
	end

	local matrix = {}
	for i = 0, len1 do
		matrix[i] = {[0] = i}
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	for i = 1, len1 do
		for j = 1, len2 do
			local cost = string.byte(str1, i) == string.byte(str2, j) and 0 or 1
			matrix[i][j] = math.min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
		end
	end

	return matrix[len1][len2]
end

local isSimilar = function(src, try, _perc)
	local srcLen = #src

	local diff = levenshtein(string.lower(src), string.lower(try))
	local maxDiff = math.ceil(srcLen * (_perc or .3))

	-- Is similar, similarity percentage
	return diff <= maxDiff, (100 - (diff / srcLen * 100))
end

local round = function(x)
	return math.floor(x + 0.5)
end

return {
	levenshtein = levenshtein,
	isSimilar = isSimilar,
	round = round
}