module Syllabi

import Markdown
import Dates
import Dates: Date, DateTime, Time, dayofweek, @dateformat_str
import YAML
import TimeZones: TimeZone, ZonedDateTime, astimezone, @tz_str

include("core.jl")
include("ical.jl")

end
