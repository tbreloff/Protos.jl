### A Pluto.jl notebook ###
# v0.15.1

using Markdown
using InteractiveUtils

# ╔═╡ 62c13856-92f9-4c51-927c-fdd52314aea4
begin
	using Pkg
	Pkg.activate()
	using Revise, Protos, BenchmarkTools
	using Protos.Specs
	import Protos.Serialization: _write_uleb, _write_key, writeproto, writefield, _read_key, readfield, jtype, wiretype
end

# ╔═╡ 81d7c2e7-6eeb-4d01-a183-1b6e669d0d7d
begin
	io3 = IOBuffer()
	_write_uleb(io3, 300)
	take!(io3)
end

# ╔═╡ e8744639-d84c-4a82-8211-5c64fcd6c416
begin
	first_bit_set = 0x80
	seven_bits_set = 0x7f
end

# ╔═╡ e5b8f286-ab63-4e33-ba40-74793d8fda94
# get the rightmost 7 bits as a UInt8
get_seven_bits(i::Integer) = UInt8(seven_bits_set & i)

# ╔═╡ 398dcf24-a03c-49be-a98b-54d6ad91b802
@assert ~zero(UInt16) |> get_seven_bits == 0x7f

# ╔═╡ 38c1160a-ba01-4a05-b226-6ca82ff7147b
# this method constructs a UIntXX from a string of 0's and 1's and 
# spaces (which are skipped)
function frombits_str(s, ::Type{T}) where T <: Unsigned
	i = zero(T)
	for c in s
		if c == ' '
			continue
		end
		i = i << 1
		if c == '1'
			i = i | one(T)
		end
	end
	i
end

# ╔═╡ bbd33f3d-27d6-483e-b3d5-b298968a952b
# some string macros for diffent sizes of UInts
begin
	macro frombits8_str(s)
		frombits_str(s, UInt8)
	end
	macro frombits64_str(s)
		frombits_str(s, UInt64)
	end
end

# ╔═╡ 5455261f-0838-49cf-9327-1b76793f1930
target300 = UInt8[frombits8"1010 1100", frombits8"0000 0010"]

# ╔═╡ 5a0b5e21-8867-4aab-8a41-1a1bc0f2b103
frombits8"1 1111 1010"

# ╔═╡ 37a46a78-0e82-4543-8584-8cab5a104292
frombits64"1 1111 1010"

# ╔═╡ 2238d1bb-2a54-4b27-8956-4863323ebc6a
md"""
# Serialization

This is a demonstration of proto serialization.  We assume a couple things:

1. We geneate immutable structs where each field is `Union{Missing, SomeType}`. This lets us treat all fields as optional and make the default value `missing`.
2. We generate a `writeproto` method for each struct which also takes in `IO`... this is just a bunch of code blocks (one for each field) that writes a key and then does field-specific serialization.
"""

# ╔═╡ fd3de1a2-28e3-4ddb-a9b1-ba358d7ba5c5
# # TODO use generated functions here
# begin
# 	writefield(io::IO, idx::Int64, val, ::Val{:uint32}) = writefield(io, idx, val, WIRETYPES[:uint32]...)
# 	writefield(io::IO, idx::Int64, val, ::Val{:string}) = writefield(io, idx, val, WIRETYPES[:string]...)
	
# 	# fallback for all others
# 	# function writefield(io::IO, idx::Int64, val, ::Val{T}) where T
# 	# 	writefield(io, idx, val, WIRETYP_LENDELIM, writeproto, readproto, typeof(val))
# 	# end
# end

# ╔═╡ 60748857-3b38-48ef-8dc3-5da3bb06515a
# function writefield(io::IO, idx::Int64, val, wiretype, writefn, readfn, T)
# 	n = 0
# 	n += _write_key(io, idx, wiretype)
# 	n += writefn(io, val)
# 	n
# end

# ╔═╡ 777d3098-1fed-4d7e-b8c3-a5896ee30c3e
# suppose this is the generated struct for a message with 2 fields
struct XXX
	f1::Union{Missing, UInt32} # uint32 f1 = 1;
	f2::Union{Missing, String} # string f2 = 2;
end

# ╔═╡ 4cacfe92-665b-4a6d-b33c-d6d780e20a1a
# then this is the serialization
function Protos.Serialization.writeproto(io::IO, x::XXX)
	n = 0
	
	# this is a generated block for uint32 values.
	# we only need the field name, field number, and field type during generation
	# though maybe we inline the next function call and remove the need
	# for generated code??
	if !ismissing(x.f1)
		n += writefield(io, 1, x.f1, Val(:uint32))
	end
	
	# same as above but for string
	if !ismissing(x.f2)
		n += writefield(io, 2, x.f2, Val(:string))
	end
	
	n
end

# ╔═╡ 7a6e441b-9d3f-4bcd-8ead-5b72cff8cb68
x = XXX(150, missing)

# ╔═╡ 7b71d148-213e-4066-9d33-92cac8e17e01
y = XXX(missing, "testing")

# ╔═╡ 35245834-c4f2-446a-ba23-7866db85833f
writeproto(y)

# ╔═╡ cf186cb3-6395-4e8c-aa4e-3cc5ecd4d6d1
struct ZZZ
	x::Union{Missing, XXX} # XXX x = 3;
end

# ╔═╡ 83d54da3-ff87-41be-ae67-118684aad6b2
# TODO this should be generated code
function Protos.Serialization.writeproto(io::IO, z::ZZZ)
	n = 0
	
	# this is a generated block for a nested proto (i.e. non-primitive).
	# as you can see we will let dispatch handle the complexity of it...
	# this code is pretty generic.
	if !ismissing(z.x)
		n += _write_key(io, 3, Protos.Serialization.WIRETYP_LENDELIM)
		# write the nested proto to a temp buffer,
		# then write then length as a varint and then the raw bytes
		bytes = writeproto(z.x)
		n += _write_uleb(io, length(bytes))
		n += write(io, bytes)
	end
	
	n
end

# ╔═╡ 8015df0d-13d2-4912-814b-8bdc70904653
# should be: [1a 03 08 96 01]
writeproto(ZZZ(XXX(150, missing)))

# ╔═╡ 000447d3-45e6-4e16-a3e8-0f5b12fcf9ef
md"""
# Deserialization

Similar to serialization, we need to generate a constructor `MyMessage(io::IO)`... i.e. a method which takes an IO stream and constructs the julia object from it.
"""

# ╔═╡ 3127f08e-d7bf-4b50-a516-719634b44046
# # TODO use generated functions here
# begin
# 	readfield(io::IO, ::Val{:uint32}) = readfield(io, WIRETYPES[:uint32]...)
# 	readfield(io::IO, ::Val{:string}) = readfield(io, WIRETYPES[:string]...)
	
# 	# fallback for all others
# 	# function writefield(io::IO, idx::Int64, val, ::Val{T}) where T
# 	# 	writefield(io, idx, val, WIRETYP_LENDELIM, writeproto, readproto, typeof(val))
# 	# end
# end

# ╔═╡ e2c93b2e-bfa7-44cd-bd10-1a5dcaa876a0
# function readfield(io::IO, wiretype, writefn, readfn, ::Type{T}) where T
# 	readfn(io, T)
# end

# ╔═╡ 7962fd02-2d67-4d12-a220-c76f289f62eb
struct XXX2
	f1::Union{Missing, UInt32} # uint32 f1 = 1;
	f2::Union{Missing, String} # string f2 = 2;
	
	# this is the additional constructor
	function XXX2(io::IO)
		# the size of this should be the number of fields
		fields = Vector{Any}(missing, 2)
		
		while (!eof(io))
			idx, wiretype = _read_key(io)
			
			# first field
			if idx == 1 # <-- this is the field number
				#      |
				# but  V  is the ordering
				fields[1] = readfield(io, Val(:uint32))
			elseif idx == 2 # <-- this is the field number
				#      |
				# but  V  is the ordering
				fields[2] = readfield(io, Val(:string))
				
			# TODO need better handling around repeated fields, maps, etc
				
			else
				skip_field(io, wiretype)
			end
		end
		
		# construct the immutable object using the fields array
		new(fields...)
	end
end

# ╔═╡ 73faa3b0-eda9-4645-a4f3-917fcd93c756
# verify that we can deserialize a previously-serialized XXX into an XXX2
begin
	iob = IOBuffer()
	writeproto(iob, x)
	seekstart(iob)
	XXX2(iob).f1 |> Int
end

# ╔═╡ c03e80d4-22a1-4c9f-bfc1-b2fabf5d1e38
begin
	generate_struct(m::Message) = """
	Base.@kwdef struct $(m.name)
		$(join(generate_struct.(m.fields), "\n    "))
	end
	"""

	generate_struct(f::NormalField) = "$(f.name)::Union{Missing, $(jtype(f.t))} = missing"
end

# ╔═╡ 467db54e-2696-43c5-aad2-854bc83758ae
begin
	is_primitive(f::NormalField) = haskey(Protos.Serialization.WIRETYPES, Symbol(f.t))
end

# ╔═╡ 2645e0fe-0329-46c2-b6da-c341a0326bff
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

# ╔═╡ b6f500d8-a98e-43d5-a0e8-9977353e5958
generate_writeproto(m::Message) = """
function Protos.Serialization.writeproto(io::IO, m::$(m.name))
	n = 0
	
$(join(generate_writefield.(m.fields), "\n"))
	
	n
end
"""

# ╔═╡ c6ac93fc-3247-4d61-a946-84bfad277e73
generate_readfield(f::NormalField, i) = """
		$(i==1 ? "" : "else")if idx == $(f.num)  # $(f.name)
			fields[$i] = readfield(io, Val(:$(Symbol(f.t))))
"""

# ╔═╡ bae37f75-a99a-4a1d-bb13-76a36d5b2c31
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

# ╔═╡ 6a0a729f-1eaa-42a8-80b4-d5b550537809
generate_message_file(m::Message) = """
$(generate_struct(m))

$(generate_readproto(m))

$(generate_writeproto(m))
"""

# ╔═╡ 5b4fd6f6-887f-4aa3-871b-466a13713d5c
pf = ProtoFile("""
syntax = "proto3";

message Test1 {
	uint32 f1 = 1;
	string f2 = 2;
}
	
message Test2 {
	Test1 x = 1;
}
""")

# ╔═╡ 3fbebff1-05a2-43c1-a3e9-c26dd4d01b5f
display_as_code(text) = Markdown.parse("""
```julia
$text
```
""")

# ╔═╡ 63feb0fa-9c6f-47bb-a955-c1920595a2d7
generate_message_file(pf.messages[1]) |> display_as_code

# ╔═╡ a541625e-fe4d-4f29-8e4f-152ddbc41e1a
generate_message_file(pf.messages[2]) |> display_as_code

# ╔═╡ 53837856-9021-408a-87eb-f93612f533bf
begin


"""
docs
"""
Base.@kwdef struct Test1
    f1::Union{Missing, UInt32} = missing
    f2::Union{Missing, AbstractString} = missing
end


function Test1(io::IO)
    # the size of this should be the number of fields
    fields = Vector{Any}(missing, 2)

    while (!eof(io))
        idx, wiretype = _read_key(io)

        if idx == 1  # f1
            fields[1] = readfield(io, Val(:uint32))

        elseif idx == 2  # f2
            fields[2] = readfield(io, Val(:string))

        else
            skip_field(io, wiretype)
        end
    end

    # construct the immutable object using the fields array
    Test1(fields...)
end


function Protos.Serialization.writeproto(io::IO, m::Test1)
    n = 0
    
    if !ismissing(m.f1)
        n += writefield(io, 1, m.f1, Val(:uint32))
    end

    if !ismissing(m.f2)
        n += writefield(io, 2, m.f2, Val(:string))
    end

    
    n
end


end

# ╔═╡ e1a879dd-ecbc-4855-9566-295a4e08880b
begin

Base.@kwdef struct Test2
    x::Union{Missing, Test1} = missing
end


function Test2(io::IO)
    # the size of this should be the number of fields
    fields = Vector{Any}(missing, 1)

    while (!eof(io))
        idx, wiretype = _read_key(io)

        if idx == 1  # x
            fields[1] = readfield(io, Val(:Test1))

        else
            skip_field(io, wiretype)
        end
    end

    # construct the immutable object using the fields array
    Test2(fields...)
end


function Protos.Serialization.writeproto(io::IO, m::Test2)
    n = 0
    
    if !ismissing(m.x)
        n += _write_key(io, 1, 2)
        # write the nested proto to a temp buffer,
        # then write then length as a varint and then the raw bytes
        bytes = writeproto(m.x)
        n += _write_uleb(io, length(bytes))
        n += write(io, bytes)
    end

    
    n
end
	
end

# ╔═╡ 310a528b-5056-46e3-8525-4649d32e6ef0
# should be 0x08 0x96 0x01
Protos.Serialization.writeproto(x)

# ╔═╡ b7bb0428-a5c2-4991-919f-6f3ce8f64644
Test1(32, "hello")

# ╔═╡ 68803c8a-c847-4f31-89a4-5eaf0b736800
t1 = Test1(f2="world")

# ╔═╡ e30c0ed0-778b-4c0e-b569-60a842ef81bc
bytes = writeproto(t1)

# ╔═╡ b67b05fa-2d5c-4448-b972-5c363a6d5a6b
Test1(IOBuffer(bytes))

# ╔═╡ 7a920003-0888-493d-b7fb-73dcfa25b5b7
t2 = Test2(Test1(f2="hi"))

# ╔═╡ e1ea9818-e913-47ed-b949-afe0be53b46e
bytes2 = writeproto(t2)

# ╔═╡ d30170e9-309a-4cb9-87cd-5049b45e3c8a
Test2(IOBuffer(bytes2))

# ╔═╡ 813080f0-54f5-467d-9915-a64b3e639953
@benchmark Test2(Test1(f1=50))

# ╔═╡ 6548f526-4eb7-4b36-94ed-d75197c40cae
@benchmark writeproto(t1)

# ╔═╡ Cell order:
# ╠═62c13856-92f9-4c51-927c-fdd52314aea4
# ╠═81d7c2e7-6eeb-4d01-a183-1b6e669d0d7d
# ╠═e8744639-d84c-4a82-8211-5c64fcd6c416
# ╠═e5b8f286-ab63-4e33-ba40-74793d8fda94
# ╠═398dcf24-a03c-49be-a98b-54d6ad91b802
# ╠═5455261f-0838-49cf-9327-1b76793f1930
# ╟─38c1160a-ba01-4a05-b226-6ca82ff7147b
# ╟─bbd33f3d-27d6-483e-b3d5-b298968a952b
# ╠═5a0b5e21-8867-4aab-8a41-1a1bc0f2b103
# ╠═37a46a78-0e82-4543-8584-8cab5a104292
# ╟─2238d1bb-2a54-4b27-8956-4863323ebc6a
# ╠═fd3de1a2-28e3-4ddb-a9b1-ba358d7ba5c5
# ╠═60748857-3b38-48ef-8dc3-5da3bb06515a
# ╠═777d3098-1fed-4d7e-b8c3-a5896ee30c3e
# ╠═4cacfe92-665b-4a6d-b33c-d6d780e20a1a
# ╠═7a6e441b-9d3f-4bcd-8ead-5b72cff8cb68
# ╠═310a528b-5056-46e3-8525-4649d32e6ef0
# ╠═7b71d148-213e-4066-9d33-92cac8e17e01
# ╠═35245834-c4f2-446a-ba23-7866db85833f
# ╠═cf186cb3-6395-4e8c-aa4e-3cc5ecd4d6d1
# ╠═83d54da3-ff87-41be-ae67-118684aad6b2
# ╠═8015df0d-13d2-4912-814b-8bdc70904653
# ╟─000447d3-45e6-4e16-a3e8-0f5b12fcf9ef
# ╠═3127f08e-d7bf-4b50-a516-719634b44046
# ╠═e2c93b2e-bfa7-44cd-bd10-1a5dcaa876a0
# ╠═7962fd02-2d67-4d12-a220-c76f289f62eb
# ╠═73faa3b0-eda9-4645-a4f3-917fcd93c756
# ╠═c03e80d4-22a1-4c9f-bfc1-b2fabf5d1e38
# ╠═b6f500d8-a98e-43d5-a0e8-9977353e5958
# ╠═467db54e-2696-43c5-aad2-854bc83758ae
# ╠═2645e0fe-0329-46c2-b6da-c341a0326bff
# ╠═bae37f75-a99a-4a1d-bb13-76a36d5b2c31
# ╠═c6ac93fc-3247-4d61-a946-84bfad277e73
# ╠═6a0a729f-1eaa-42a8-80b4-d5b550537809
# ╠═5b4fd6f6-887f-4aa3-871b-466a13713d5c
# ╟─3fbebff1-05a2-43c1-a3e9-c26dd4d01b5f
# ╠═63feb0fa-9c6f-47bb-a955-c1920595a2d7
# ╠═a541625e-fe4d-4f29-8e4f-152ddbc41e1a
# ╠═53837856-9021-408a-87eb-f93612f533bf
# ╠═e1a879dd-ecbc-4855-9566-295a4e08880b
# ╠═b7bb0428-a5c2-4991-919f-6f3ce8f64644
# ╠═68803c8a-c847-4f31-89a4-5eaf0b736800
# ╠═e30c0ed0-778b-4c0e-b569-60a842ef81bc
# ╠═b67b05fa-2d5c-4448-b972-5c363a6d5a6b
# ╠═7a920003-0888-493d-b7fb-73dcfa25b5b7
# ╠═e1ea9818-e913-47ed-b949-afe0be53b46e
# ╠═d30170e9-309a-4cb9-87cd-5049b45e3c8a
# ╠═813080f0-54f5-467d-9915-a64b3e639953
# ╠═6548f526-4eb7-4b36-94ed-d75197c40cae
