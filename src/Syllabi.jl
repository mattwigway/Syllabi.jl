module Syllabi

import Markdown
import Dates
import Dates: Date, dayofweek, @dateformat_str
import YAML

const DATEFORMAT = dateformat"U d"
const DATEFORMAT_DAY = dateformat"d"
const ANCHOR_REGEX = r"%%((?:[[:alnum:]]|[_\-])+)~?(-?[0-9]+)?"
const XREF_REGEX = r"@@(?:[[:alnum:]]|[_\-])+"


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
        if current ∉ s.excluded_dates && current ≤ s.end_date
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

# markdown elements where the content is in the vector .text
const ElementWithText = Union{Markdown.Header, Markdown.Italic, Markdown.Bold, Markdown.Link}

# markdown elements where the content is in the vector .content
const ElementWithContent = Union{Markdown.Paragraph}

function parse_references!(s::AbstractString, cross_refs, class_dates, current_date_index)
    for anchor in eachmatch(ANCHOR_REGEX, s)
        anchtext = lowercase(anchor.captures[1])
        if haskey(cross_refs, anchtext)
            println("Warn: duplicate anchor definition $anchtext")
        else
            # figure out offsets - ~ means offset in class days
            class_day_offset = isnothing(anchor.captures[2]) ? 0 : parse(Int64, anchor.captures[2])
            cross_refs[anchtext] = class_dates[current_date_index + class_day_offset]
        end
    end

    # remove anchors from text
    return replace(s, ANCHOR_REGEX=>"")
end

function parse_references!(element::ElementWithText, cross_refs, class_dates, current_date_index)
    map!(t -> parse_references!(t, cross_refs, class_dates, current_date_index), element.text, element.text)
    return element
end

function parse_references!(element::ElementWithContent, cross_refs, class_dates, current_date_index)
    map!(t -> parse_references!(t, cross_refs, class_dates, current_date_index), element.content, element.content)
    return element
end

function parse_references!(element::Markdown.List, cross_refs, class_dates, current_date_index)
    map!(i -> parse_references!(i, cross_refs, class_dates, current_date_index), element.items, element.items)
    return element
end

function parse_references!(element::Markdown.Table, cross_refs, class_dates, current_date_index)
    map!(r -> parse_references!(r, cross_refs, class_dates, current_date_index), element.rows, element.rows)
end

function parse_references!(vec::AbstractVector, cross_refs, class_dates, current_date_index)
    map!(r -> parse_references!(r, cross_refs, class_dates, current_date_index), vec, vec)
    return vec
end

# Note: this version does not actually mutate its arguments, but needs to have the same signature as the ones that do
replace_references!(s::AbstractString, cross_refs) = replace(s, XREF_REGEX=>(r -> Dates.format(cross_refs[lowercase(r[3:end])], DATEFORMAT)))

function replace_references!(element::ElementWithText, cross_refs)
    map!(t -> replace_references!(t, cross_refs), element.text, element.text)
    return element
end

function replace_references!(element::ElementWithContent, cross_refs)
    map!(t -> replace_references!(t, cross_refs), element.content, element.content)
    return element
end

function replace_references!(element::Markdown.List, cross_refs)
    map!(t -> replace_references!(t, cross_refs), element.items, element.items)
    return element
end

function replace_references!(element::Markdown.Table, cross_refs)
    map!(t -> replace_references!(t, cross_refs), element.rows, element.rows)
    return element
end

function replace_references!(vec::AbstractVector, cross_refs)
    map!(t -> replace_references!(t, cross_refs), vec, vec)
    return vec
end

replace_references!(lb::Markdown.LineBreak, _) = lb

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

    # split only on lines that are ---, not any line that contains ---
    # ^ and $ refer to the entire document, not individual lines, for split()
    doc = Markdown.parse(last(split(body, r"(^|\n)---\n")))
    output = []
    
    # find the schedule section
    class_dates = get_all_class_dates(syllabus)
    current_date_index = 1
    next_date_index = 1
    schedule_day_header_level = 0
    in_schedule_section = false

    # run this twice to get cross-refs right
    cross_refs = Dict{String, Date}()

    for pass in [:references, :output]
        if pass == output
            println("Referenced dates: $cross_refs")
        end
        # NB anchors can't be in schedule headers
        for element in doc.content
            # handle cross references

            if pass == :references
                if in_schedule_section
                    parse_references!(element, cross_refs, class_dates, current_date_index)
                end
            else
                replace_references!(element, cross_refs)
            end

            if element isa Markdown.Header
                hlevel = get_header_level(element)

                if !in_schedule_section
                    # are we entering a schedule section?
                    if contains(lowercase(element.text[1]), "schedule")
                        in_schedule_section = true
                        schedule_day_header_level = hlevel + 1
                    end

                    if pass == :output
                        push!(output, element)
                    end
                else
                    # we are in a schedule section
                    if hlevel == schedule_day_header_level
                        text, ndays = parse_header(element.text[1])
                        current_date_index = next_date_index

                        if current_date_index + ndays - 1 > length(class_dates)
                            error("Too many class dates (occurred at day $text)")
                        end    

                        # figure out if we need to add excluded dates - do this here so it's after any content associated with previous date
                        for (date, ex_text) in zip(syllabus.excluded_dates, syllabus.excluded_date_reasons)
                            if date < class_dates[current_date_index] && (current_date_index == 1 || date > class_dates[current_date_index - 1])
                                if pass == :output
                                    push!(output, Markdown.Header{schedule_day_header_level}(["$(Dates.format(date, DATEFORMAT)): No class"]))
                                    push!(output, Markdown.Paragraph([ex_text]))
                                end
                            end
                        end


                        # add the date
                        dates = class_dates[current_date_index:current_date_index+(ndays - 1)]
                        next_date_index = current_date_index + ndays
                        prev, rest = Iterators.peel(dates)
                        formatted_dates = [Dates.format(prev, DATEFORMAT)]
                        for date in rest
                            if Dates.month(date) == Dates.month(prev)
                                # don't repeat month
                                push!(formatted_dates, Dates.format(date, DATEFORMAT_DAY))
                            else
                                push!(formatted_dates, Dates.format(date, DATEFORMAT))
                            end
                            prev = date
                        end

                        date_text = join(formatted_dates, ", ")

                        if pass == :output
                            push!(output, Markdown.Header{schedule_day_header_level}(["$date_text: $text"]))
                        end
                    elseif hlevel < schedule_day_header_level
                        # no longer in a schedule section
                        in_schedule_section = false
                        current_date_index = 1
                        next_date_index = 1

                        if pass == :output
                            push!(output, element)
                        end
                    else
                        if pass == :output
                            push!(output, element)
                        end
                    end
                end
            else
                if pass == :output
                    push!(output, element)
                end
            end
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
