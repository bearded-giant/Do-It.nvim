-- Logic for parsing dates & adding/removing due dates

local vim = vim

local DueDates = {}

function DueDates.setup(M, config)
	local function parse_date(date_str)
		local month, day, year = date_str:match("^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
		if not (month and day and year) then
			return nil, "Invalid date format (expected MM/DD/YYYY)"
		end

		month = tonumber(month)
		day = tonumber(day)
		year = tonumber(year)

		local function is_leap_year(y)
			return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
		end

		local days_in_month = {
			31,
			is_leap_year(year) and 29 or 28,
			31,
			30,
			31,
			30,
			31,
			31,
			30,
			31,
			30,
			31,
		}

		if month < 1 or month > 12 then
			return nil, "Invalid month"
		end
		if day < 1 or day > days_in_month[month] then
			return nil, "Invalid day for month"
		end

		return os.time({
			year = year,
			month = month,
			day = day,
			hour = 0,
			min = 0,
			sec = 0,
		})
	end

	function M.add_due_date(index, date_str)
		local todo = M.todos[index]
		if not todo then
			return false, "Todo not found"
		end

		local timestamp, err = parse_date(date_str)
		if timestamp then
			todo.due_at = timestamp
			M.save_to_disk()
			return true
		else
			return false, err
		end
	end

	function M.remove_due_date(index)
		local todo = M.todos[index]
		if not todo then
			return false
		end
		todo.due_at = nil
		M.save_to_disk()
		return true
	end

	function M.add_time_estimation(index, hours)
		local todo = M.todos[index]
		if not todo then
			return false, "Todo not found"
		end
		if type(hours) ~= "number" or hours < 0 then
			return false, "Invalid time estimation"
		end
		todo.estimated_hours = hours
		M.save_to_disk()
		return true
	end

	function M.remove_time_estimation(index)
		local todo = M.todos[index]
		if todo then
			todo.estimated_hours = nil
			M.save_to_disk()
			return true
		end
		return false
	end
end

return DueDates
