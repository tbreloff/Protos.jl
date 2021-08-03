
module Gen

using ..Specs

export generate

_indent(indent) = " " ^ (4 * indent)

"""
indent the whole block
"""
indent(s::AbstractString, indent_num) = replace(s, "\n" => "\n$(_indent(indent_num))")

function comments(comment)
    ismissing(comment) ? "" : "#" * replace(comment, "\n" => "\n#") * "\n"
end

"""
generate a bunch of string representations for each element in arr.
the func should return a string representation of each element.
"""
function generate(arr::Vector)
    join(map(generate, arr), "\n\n")
end

function generate(f::NormalField)
    c = comments(f.comments)
    """$(c)$(f.name)::$(to_type(f.t))"""
end

function generate(f::MapField)
    c = comments(f.comments)
    kt = to_type(f.key_type)
    vt = to_type(f.value_type)
    """$(c)$(f.name)::Dict{$kt, $vt}"""
end

function generate(f::OneOf)
    c = comments(f.comments)
    """$(c)# ONEOF: $(f.name)
    $(generate(f.fields))"""
end

function generate(m::Message; prefix="")
    c = comments(m.comments)
    """$(c)struct $(prefix)$(m.name)
        $(indent(generate(m.fields), 1))
    end
    $(generate(m.inner_messages))
    $(generate(m.inner_enums))"""
end

function generate(ev::EnumValue)
    c = comments(ev.comments)
    """$(c)$(ev.name) = $(ev.num)"""
end

function generate(es::EnumSpec; prefix="")
    """$(comments(es.comments))@enum $(prefix)$(es.name) begin
        $(indent(generate(es.values), 1))
    end"""
end

function generate(pf::ProtoFile)
    c = comments(pf.comments)
    """$(c)
    # TODO imports as using relative modules

    $(generate(pf.enums))
    
    $(generate(pf.messages))
    
    $(generate(pf.services))
    """
end

end # module
