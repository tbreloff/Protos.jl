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
"""

# ╔═╡ 2a85c2ae-cfcd-4e2e-8efe-b58ab29f6b5d


# ╔═╡ db015138-0861-492e-9e0d-41665247bf2c
begin
	function todocs(a::AbstractVector)
		join(map(todocs, a), "\n")
	end
	function todocs(s::Protos.Service)
		"""
		# Service: $(s.name)
		
		| Endopint | Request | Response | Comments |
		| --- | --- | --- | --- |
		$(todocs(s.rpcs))
		"""
	end
	function todocs(r::Protos.Rpc)
		"""
		| $(r.name) | $(r.input_type) | $(r.output_type) | $(r.comments) |
		"""
	end
end

# ╔═╡ 7b1f28f8-38ca-47a7-b32d-65ba97c9e455
docs = """
# $(pf.package)

$(pf.comments)

$(todocs(pf.services))
"""

# ╔═╡ Cell order:
# ╠═4780a67c-fd4d-11eb-1537-7db97c4ddf01
# ╠═335cd316-44ea-4969-a645-bf4696252426
# ╟─45548429-1158-4534-9c6b-397f90fc8a0f
# ╠═c1f7667d-b4dd-4f06-84f2-2154d2ac34a7
# ╟─055ed3ec-6b58-428e-a99d-ab5b04aa7765
# ╠═da86052d-8111-47c5-b88c-e14f9d552e8f
# ╟─a5d6bb5e-31da-47cc-b9ff-39bda7fa423c
# ╠═2a85c2ae-cfcd-4e2e-8efe-b58ab29f6b5d
# ╠═db015138-0861-492e-9e0d-41665247bf2c
# ╠═7b1f28f8-38ca-47a7-b32d-65ba97c9e455
