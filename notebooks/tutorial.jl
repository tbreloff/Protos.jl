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
	using Protos
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
        InnerMessage inner_message = 3;
    }
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
