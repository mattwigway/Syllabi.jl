module Syllabi

import Markdown
import Dates
import Dates: Date, dayofweek, @dateformat_str
import YAML

const DATEFORMAT = dateformat"U d"

# Write your package code here.
struct Syllabus
    start_date::Date
    end_date::Date
    days_of_week::Vector{Int64}  # using Dates.Monday, Dates.Tuesday, etc.
    excluded_dates::Vector{Date}
    excluded_date_reasons::Vector{String}
    added_dates::Vector{Date}
end

function get_all_class_dates(s::Syllabus)
    result = Vector{Date}()
    current = s.start_date
    if dayofweek(current) ∈ s.days_of_week && current ∉ s.excluded_dates
        push!(result, current)
    end

    while current ≤ s.end_date
        current = Dates.tonext(d -> dayofweek(d) ∈ s.days_of_week, current)
        if current ∉ s.excluded_dates
            push!(result, current)
        end
    end

    push!.(Ref(result), s.added_dates)

    return sort(unique(result))
end

parse_day_of_week(x::Char) = parse_day_of_week("$x")
parse_day_of_week(x::AbstractString) = if uppercase(x) ∈ ["M", "MON", "MONDAY"]
    Dates.Monday
elseif uppercase(x) ∈ ["T", "TUE", "TUESDAY"]
    Dates.Tuesday
elseif uppercase(x) ∈ ["W", "WED", "WEDNESDAY"]
    Dates.Wednesday
elseif uppercase(x) ∈ ["R", "THU", "THURSDAY"]
    Dates.Thursday
elseif uppercase(x) ∈ ["F", "FRI", "FRIDAY"]
    Dates.Friday
elseif uppercase(x) ∈ ["S", "SAT", "SATURDAY"]
    Dates.Saturday
elseif uppercase(x) ∈ ["U", "SUN", "SUNDAY"]
    Dates.Sunday
end

get_header_level(::Markdown.Header{T}) where T = T

# figure out multi-day classes
function parse_header(str)
    exp = r"(.*) ?\{.*days ?= ?([0-9]+)\}"
    if contains(str, exp)
        m = match(exp, str)
        return m.captures[1], parse(Int64, m.captures[2])
    else
        return str, 1
    end
end

function parse_doc(body::AbstractString)
    front_matter = YAML.load(body)

    excluded_dates = [x[1] for x in front_matter["excluded_dates"]]
    excluded_date_reasons = [x[2] for x in front_matter["excluded_dates"]]
    exsort = sortperm(excluded_dates)

    # build the syllabus object
    syllabus = Syllabus(
        front_matter["start_date"],
        front_matter["end_date"],
        parse_day_of_week.(collect(front_matter["days_of_week"])),
        excluded_dates[exsort],
        excluded_date_reasons[exsort],
        front_matter["added_dates"]
    )

    doc = Markdown.parse(last(split(body, "---")))
    output = []
    
    # find the schedule section
    class_dates = get_all_class_dates(syllabus)
    current_date_index = 1
    schedule_day_header_level = 0
    in_schedule_section = false

    for element in doc.content
        if element isa Markdown.Header
            hlevel = get_header_level(element)

            if !in_schedule_section
                # are we entering a schedule section?
                if contains(lowercase(element.text[1]), "schedule")
                    in_schedule_section = true
                    schedule_day_header_level = hlevel + 1
                end

                push!(output, element)
            else
                # we are in a schedule section
                if hlevel == schedule_day_header_level
                    # figure out if we need to add excluded dates - do this here so it's after any content associated with previous date
                    for (date, text) in zip(syllabus.excluded_dates, syllabus.excluded_date_reasons)
                        if date < class_dates[current_date_index] && (current_date_index == 1 || date > class_dates[current_date_index - 1])
                            push!(output, Markdown.Header{schedule_day_header_level}(["$(Dates.format(date, DATEFORMAT)): No class"]))
                            push!(output, Markdown.Paragraph([text]))
                        end
                    end


                    # add the date
                    text, ndays = parse_header(element.text[1])
                    dates = class_dates[current_date_index:current_date_index+(ndays - 1)]
                    current_date_index += ndays
                    date_text = join(Dates.format.(dates, DATEFORMAT), ", ")
                    push!(output, Markdown.Header{schedule_day_header_level}(["$date_text: $text"]))
                elseif hlevel > schedule_day_header_level
                    # no longer in a schedule section
                    in_schedule_section = false
                    current_date_index = 1
                    push!(output, element)
                else
                    push!(output, element)
                end
            end
        else
            push!(output, element)
        end
    end

    return Markdown.MD(output)
end

function render(insymd, outmd)
    inp = open(x -> read(x, String), insymd)
    result = parse_doc(inp)
    open(outmd, "w") do mdout
        print(mdout, result)
    end
end

end
