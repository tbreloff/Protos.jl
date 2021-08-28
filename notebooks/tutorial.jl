### A Pluto.jl notebook ###
# v0.15.1

using Markdown
using InteractiveUtils

# ╔═╡ 4780a67c-fd4d-11eb-1537-7db97c4ddf01
begin
	# here we are activating the Protos environment
	import Pkg
	Pkg.activate(joinpath(@__DIR__, ".."))
	
	# then use it
	using Protos, Parameters, ProtoBuf
end

# ╔═╡ 821a55e1-2f2a-41d4-81bb-6c52a889c3dc
md"This block just activates the local Protos environment for this notebook and imports the Protos library."

# ╔═╡ db8e2b81-6bd1-4b77-8717-f80b4d249666
md"Here's a test proto3 file. If the syntax is unfamiliar, check out the [documentation](https://developers.google.com/protocol-buffers/docs/proto3)."

# ╔═╡ 335cd316-44ea-4969-a645-bf4696252426
test_file = """
/*
This is a file-wide comment.
*/

syntax = "proto3";

package some.package.name;

option java_package = "some.other.package.name";
option java_multiple_files = true;


// these comments 
// will get combined
message MyMessage1 {
    // comment
    bool value = 1;
    /* another
        comment */
    map<string, uint32> m = 2;

    // this comment will get thrown away
}

// another message
message MyMessage2 {

    // an inner message
    message InnerMessage {
        string x = 1;
    }

    // oneof comment
    oneof a_one_of {
        sfixed32 value = 1;
        // comment
        InnerMessage inner_message = 2;
    }

	MyMessage1 ref = 3;
}

enum AnEnum {
    // comment
    UNKNOWN = 0;
    SOMETHING = 1;
}

// a grpc service
service MyService {
    // an endpoint
    rpc DoSomething(DoSomethingRequest) returns (stream DoSomethingResponse) {};
}
""";

# ╔═╡ 45548429-1158-4534-9c6b-397f90fc8a0f
md"We can parse proto file text into structured form with `parse_proto`"

# ╔═╡ c1f7667d-b4dd-4f06-84f2-2154d2ac34a7
parsed = parse_proto(test_file)

# ╔═╡ 055ed3ec-6b58-428e-a99d-ab5b04aa7765
md"""
The structured content above is great, but the nested NamedTuples don't allow for nice dispatch when processing the structure.

If you pass the parsed structure to the `ProtoFile` constructor, you'll get a dispatch-friendly structure of the proto file.
"""

# ╔═╡ da86052d-8111-47c5-b88c-e14f9d552e8f
pf = ProtoFile(parsed)

# ╔═╡ ebbf228f-d511-46c2-b6f2-62196f693f5c
begin
	
	using Protos.Specs

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
	function generate(arr::Vector; kw...)
		join([generate(x; kw...) for x in arr], "\n")
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
		"""
		$(c)@with_kw_noshow struct $(prefix)$(m.name)
			$(indent(generate(m.fields), 1))
		end
		$(generate(m.inner_messages; prefix=m.name*'_'))
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
		
		# this package gives us lots of nice options for 
		# constructors with default values
		using Parameters
		
		# TODO imports as using relative modules

		$(generate(pf.enums))

		$(generate(pf.messages))

		$(generate(pf.services))
		"""
	end

	function generate(service::Service)
		c = comments(service.comments)
		"""$c
		# TODO service: $(service.name) with endpoints:
			$(join([rpc.name for rpc in service.rpcs], "\n\t"))
		"""
	end
	
	"""
	create markdown which will render nicely in Pluto
	"""
	function showcode(code::AbstractString)
		Markdown.parse("""
		```
		$(generate(pf))
		```
		""")
	end
	
end; #begin

# ╔═╡ a5d6bb5e-31da-47cc-b9ff-39bda7fa423c
md"""
Let's use the `ProtoFile` object to create some documentation for our service!

One easy way to do this is to use dispatch for a new method to return a string for each type of spec object that you care to process. We'll focus on gRPC service documentation for simplicity.
"""

# ╔═╡ db015138-0861-492e-9e0d-41665247bf2c
begin
	function todocs(a::AbstractVector)
		join(map(todocs, a), "\n")
	end
	function todocs(s::Protos.Specs.Service)
		"""
		# Service: $(s.name)
		
		| Endopint | Request | Response | Comments |
		| --- | --- | --- | --- |
		$(todocs(s.rpcs))
		"""
	end
	function todocs(r::Protos.Specs.Rpc)
		"""
		| $(r.name) | $(r.input_type) | $(r.output_type) | $(r.comments) |
		"""
	end
	function todocs(p::ProtoFile)
		"""
		# $(pf.package)

		$(pf.comments)

		$(todocs(pf.services))
		"""
	end
end

# ╔═╡ 71559e44-9483-4034-b0db-f3e1d7d19992
Markdown.parse(todocs(pf))

# ╔═╡ 4051727e-2ef9-4822-b050-5e918bd75cb7
md"We'll use this same pattern to generate code in order to interact with proto data."

# ╔═╡ 11c2697f-5833-42a8-9772-c10e8fd9af15
md"TODO: We can serialize to bytes with `write_proto` and `read_proto` methods from [ProtoBuf.jl](https://github.com/JuliaIO/ProtoBuf.jl)"

# ╔═╡ 691bdc92-f816-480b-9c9e-3ac46c6a2157
showcode(generate(pf))

# ╔═╡ 91b6e663-3236-4d27-a113-209e891d8816
md"""
Let's look at the definition of `MyMessage1`:

- We define an immutable struct with the same name.
- We use the `@with_kw_noshow` macro from [Parameters.jl](https://github.com/mauro3/Parameters.jl) which allows us to set default values, provides convenience construction with keyword args, etc.
- We have fields which line up with the defined proto fields.
"""

# ╔═╡ ac3fb510-e9de-4a0f-8a38-9d0a084bf17d
@with_kw_noshow struct MyMessage1
	# comment
    value::Bool
    # another
    #        comment 
    m::Dict{String, UInt32}
end

# ╔═╡ 89725058-be3e-4bb0-86bb-da8324673f10
md"Instantiating a new `MyMessage1` is straightforward:"

# ╔═╡ d8b62e66-2b8b-4947-9550-9414b6164b32
mm1 = MyMessage1(value=true, m=Dict("a"=>1, "b"=>2))

# ╔═╡ ef5f5791-fa0e-424e-ba6a-c5e9d69af764
# TODO: round trip to/from bytes

# ╔═╡ 043ad351-6ee8-4d08-9b86-e1817849b18c
begin
	proto_default(::Type) = missing
	proto_default(::Type{T}) where {T<:Number} = zero(T)
	proto_default(::Type{T}) where {T<:AbstractString} = ""
	proto_default(::Type{Bool}) = false
	proto_default(::Type{Vector{T}}) where T = T[]
end;

# ╔═╡ ba3e662b-40fb-4fe9-94a2-148ba0e97110
proto_default(UInt32)

# ╔═╡ d88b10ae-41f2-4e0d-b97f-65fb252ac926
proto_default(String)

# ╔═╡ 259ccbcc-2974-48e3-8cb0-4c494da6435f
proto_default(Bool)

# ╔═╡ d8415c2b-223c-402f-b1c5-15cf8e40de5a
proto_default(Vector{MyMessage1})

# ╔═╡ e431141c-3879-4ce8-830e-bbf7f0d1178a
proto_default(MyMessage1)

# ╔═╡ Cell order:
# ╟─821a55e1-2f2a-41d4-81bb-6c52a889c3dc
# ╠═4780a67c-fd4d-11eb-1537-7db97c4ddf01
# ╟─db8e2b81-6bd1-4b77-8717-f80b4d249666
# ╠═335cd316-44ea-4969-a645-bf4696252426
# ╟─45548429-1158-4534-9c6b-397f90fc8a0f
# ╠═c1f7667d-b4dd-4f06-84f2-2154d2ac34a7
# ╟─055ed3ec-6b58-428e-a99d-ab5b04aa7765
# ╠═da86052d-8111-47c5-b88c-e14f9d552e8f
# ╟─a5d6bb5e-31da-47cc-b9ff-39bda7fa423c
# ╠═db015138-0861-492e-9e0d-41665247bf2c
# ╠═71559e44-9483-4034-b0db-f3e1d7d19992
# ╟─4051727e-2ef9-4822-b050-5e918bd75cb7
# ╠═ebbf228f-d511-46c2-b6f2-62196f693f5c
# ╟─11c2697f-5833-42a8-9772-c10e8fd9af15
# ╠═691bdc92-f816-480b-9c9e-3ac46c6a2157
# ╟─91b6e663-3236-4d27-a113-209e891d8816
# ╠═ac3fb510-e9de-4a0f-8a38-9d0a084bf17d
# ╟─89725058-be3e-4bb0-86bb-da8324673f10
# ╠═d8b62e66-2b8b-4947-9550-9414b6164b32
# ╠═ef5f5791-fa0e-424e-ba6a-c5e9d69af764
# ╠═043ad351-6ee8-4d08-9b86-e1817849b18c
# ╠═ba3e662b-40fb-4fe9-94a2-148ba0e97110
# ╠═d88b10ae-41f2-4e0d-b97f-65fb252ac926
# ╠═259ccbcc-2974-48e3-8cb0-4c494da6435f
# ╠═d8415c2b-223c-402f-b1c5-15cf8e40de5a
# ╠═e431141c-3879-4ce8-830e-bbf7f0d1178a
