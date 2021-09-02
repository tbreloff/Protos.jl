
module Gen

using ..Specs
using ..Serialization

export generate_message_file

_indent(indent) = " " ^ (4 * indent)

"""
indent the whole block
"""
indent(s::AbstractString, indent_num) = replace(s, "\n" => "\n$(_indent(indent_num))")

function comments(comment)
    ismissing(comment) ? "" : "#" * replace(comment, "\n" => "\n#") * "\n"
end


const JTYPES = Dict{Symbol, Symbol}(
    :int32    => :Int32,
    :int64    => :Int64,
    :uint32   => :UInt32,
    :uint64   => :UInt64,
    :sint32   => :Int32,
    :sint64   => :Int64,
    :bool     => :Bool,
    :enum     => :Int32,
    :fixed64  => :UInt64,
    :sfixed64 => :Int64,
    :double   => :Float64,
    :string   => :AbstractString,
    :bytes    => Symbol("Vector{UInt8}"),
    # :map      => :Dict,
    :fixed32  => :UInt32,
    :sfixed32 => :Int32,
    :float    => :Float32
)

jtype(::Missing) = :Missing
jtype(s::AbstractString) = jtype(Symbol(s))
jtype(s::Symbol) = haskey(JTYPES, s) ? JTYPES[s] : s


is_primitive(_type) = haskey(JTYPES, Symbol(_type))

# ---------------------------------------

generate_struct(m::Message) = """
Base.@kwdef struct $(m.name)
    $(join(generate_struct.(m.fields), "\n    "))
end
"""

generate_struct(f::NormalField) = "$(f.name)::Union{Missing, $(jtype(f.t))} = missing"

generate_writeproto(m::Message) = """
function Protos.Serialization.writeproto(io::IO, m::$(m.name))
	n = 0
	
$(join(generate_writefield.(m.fields), "\n"))
	
	n
end
"""

function generate_writefield(f::NormalField)
	if is_primitive(f)
		"""
			if !ismissing(m.$(f.name))
				n += writefield(io, $(f.num), m.$(f.name), Val(:$(f.t)))
			end
		"""
	else
		"""
			if !ismissing(m.$(f.name))
				n += _write_key(io, $(f.num), $(wiretype(f.t)))
				# write the nested proto to a temp buffer,
				# then write then length as a varint and then the raw bytes
				bytes = writeproto(m.$(f.name))
				n += _write_uleb(io, length(bytes))
				n += write(io, bytes)
			end
		"""
	end
end

generate_readproto(m::Message) = """
function $(m.name)(io::IO)
	# the size of this should be the number of fields
	fields = Vector{Any}(missing, $(length(m.fields)))

	while (!eof(io))
		idx, wiretype = _read_key(io)

$(join([generate_readfield(f, i) for (i, f) in enumerate(m.fields)], "\n"))
		else
			skip_field(io, wiretype)
		end
	end

	# construct the immutable object using the fields array
	$(m.name)(fields...)
end
"""

generate_readfield(f::NormalField, i) = """
		$(i==1 ? "" : "else")if idx == $(f.num)  # $(f.name)
			fields[$i] = readfield(io, Val(:$(Symbol(f.t))))
"""

generate_message_file(m::Message) = """
$(generate_struct(m))

$(generate_readproto(m))

$(generate_writeproto(m))
"""

# ---------------------------------------


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
