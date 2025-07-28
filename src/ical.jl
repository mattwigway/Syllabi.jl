struct Event{D <: Union{Date, DateTime}}
    uid::String
    summary::String
    description::String
    location::String
    dtstart::D
    dtend::D
    alarm::String
    tz::String
end

struct Calendar
    source::Union{String, Nothing}
    refresh_interval::String
    events::Vector{Event}
end

writecrlf(io, str) = write(io, "$str\r\n")

ical_esc(s) = escape_string(s, (',', ';'))

ical_date(d::Date, _) = Dates.format(d, dateformat";VALUE=DATE:yyyymmdd")
function ical_date(d::DateTime, tzname) 
    tz = TimeZone(tzname)
    zdt = ZonedDateTime(d, tz)
    Dates.format(astimezone(zdt, tz"UTC"), dateformat":yyyymmddTHHMMSS") * "Z"
end

function Base.write(io::IO, e::Event)
    writecrlf(io, "BEGIN:VEVENT")
    writecrlf(io, "UID:$(e.uid)")
    writecrlf(io, "SUMMARY:$(ical_esc(e.summary))")
    writecrlf(io, "DESCRIPTION:$(ical_esc(e.description))")
    writecrlf(io, "LOCATION:$(ical_esc(e.location))")
    writecrlf(io, "DTSTART$(ical_date(e.dtstart, e.tz))")
    writecrlf(io, "DTEND$(ical_date(e.dtend, e.tz))")
    writecrlf(io, "DTSTAMP$(ical_date(Dates.now(Dates.UTC), "UTC"))")
    writecrlf(io, "BEGIN:VALARM")
    writecrlf(io, "TRIGGER:$(e.alarm)")
    writecrlf(io, "ACTION:DISPLAY")
    writecrlf(io, "SUMMARY:$(ical_esc(e.summary))")
    writecrlf(io, "DESCRIPTION:$(ical_esc(e.description))")
    writecrlf(io, "END:VALARM")
    writecrlf(io, "END:VEVENT")
end

function Base.write(io::IO, cal::Calendar)
    writecrlf(io, "BEGIN:VCALENDAR")
    writecrlf(io, "VERSION:2.0")
    writecrlf(io, "PRODID:-//indicatrix.org//Syllabi.jl//1.0")
    writecrlf(io, "SOURCE:$(ical_esc(cal.source))")
    writecrlf(io, "REFRESH-INTERVAL;VALUE=DURATION:$(cal.refresh_interval)")
    writecrlf(io, "CALSCALE:GREGORIAN")
    writecrlf(io, "METHOD:PUBLISH")
    for e in cal.events
        write(io, e)
    end
    writecrlf(io, "END:VCALENDAR")
end