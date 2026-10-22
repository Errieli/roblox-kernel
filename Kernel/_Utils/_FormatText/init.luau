-- // Constants
local SUFFIXES = {
	-- 0 a 9 (Milhões a Nonilhões)
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No",
	-- 10 a 19 (Decilhões)
	"Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod",
	-- 20 a 29 (Vigintilhões)
	"Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Novg",
	-- 30 a 39 (Trigintilhões)
	"Tg", "Utg", "Dtg", "Ttg", "Qatg", "Qitg", "Sxtg", "Sptg", "Octg", "Notg",
	-- 40 a 49 (Quadragintilhões)
	"Qd", "Uqd", "Dqd", "Tqd", "Qaqd", "Qiqd", "Sxqd", "Spqd", "Ocqd", "Noqd",
	-- 50 a 59 (Quinquagintilhões)
	"Qq", "Uqq", "Dqq", "Tqq", "Qaqq", "Qiqq", "Sxqq", "Spqq", "Ocqq", "Noqq",
	-- 60 a 69 (Sexagintilhões)
	"Sxg", "Usxg", "Dsxg", "Tsxg", "Qasxg", "Qisxg", "Sxsxg", "Spsxg", "Ocsxg", "Nosxg",
	-- 70 a 79 (Septuagintilhões)
	"Spg", "Uspg", "Dspg", "Tspg", "Qaspg", "Qispg", "Sxspg", "Spspg", "Ocspg", "Nospg",
	-- 80 a 89 (Octogintilhões)
	"Ocg", "Uocg", "Docg", "Tocg", "Qaocg", "Qiocg", "Sxocg", "Spocg", "Ococg", "Noocg",
	-- 90 a 99 (Nonagintilhões)
	"Nog", "Unog", "Dnog", "Tnog", "Qanog", "Qinog", "Sxnog", "Spnog", "Ocnog", "Nonog",
	-- 100 a 109 (Centilhões)
	"Cnt", "Ucnt", "Dcnt", "Tcnt", "Qacnt", "Qicnt", "Sxcnt", "Spcnt", "Occnt", "Nocnt",
	-- 110 a 119 (Decicentilhões)
	"Dccnt", "Udccnt", "Ddccnt", "Tdccnt", "Qadccnt", "Qidccnt", "Sxdccnt", "Spdccnt", "Ocdccnt", "Nodccnt",
	-- 120 a 129 (Viginticentilhões)
	"Vgcnt", "Uvgcnt", "Dvgcnt", "Tvgcnt", "Qavgcnt", "Qivgcnt", "Sxvgcnt", "Spvgcnt", "Ocvgcnt", "Novgcnt"
}

local function toScientificNotation(number: number)
	if number == 0 then return "0" end
	local sign = number < 0 and "-" or ""
	number = math.abs(number)
	local exponent = math.floor(math.log10(number))
	local mantissa = math.floor(number / (10 ^ exponent) * 100) / 100
	return sign .. mantissa .. "e" .. exponent
end

-- Return the number in a formated version
return function(number: number, idp: number?): string
	if typeof(number) ~= "number" then return "0" end
	if number == 0 then return "0" end
	if number == math.huge or number == -math.huge or number ~= number then return "∞" end
	
	if _G.ScientificNotation and math.abs(number) >= 1e6 then
		return toScientificNotation(number)
	end

	idp = idp or 2

	local absNumber = math.abs(number)
	local exp = math.floor(math.log(absNumber, 1000))

	if exp < 0 then
		return ("%." .. idp .. "f"):format(number)
	end

	local suffix = SUFFIXES[exp + 1] or ("e+" .. exp)
	local norm = number / (1000 ^ exp)

	local formatted = ("%." .. idp .. "f"):format(norm)

	return formatted .. suffix
end