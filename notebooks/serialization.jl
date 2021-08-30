### A Pluto.jl notebook ###
# v0.15.1

using Markdown
using InteractiveUtils

# ╔═╡ 7dc6f22a-4405-43b6-8d54-adc57f9c934f
# this is copied from ProtoBuf's codec.jl
begin
	const MSB = 0x80
	const MASK7 = 0x7f
	const MASK8 = 0xff
	const MASK3 = 0x07

	const WIRETYP_VARINT   = 0
	const WIRETYP_64BIT    = 1
	const WIRETYP_LENDELIM = 2
	const WIRETYP_GRPSTART = 3   # deprecated
	const WIRETYP_GRPEND   = 4   # deprecated
	const WIRETYP_32BIT    = 5

	"""
	The abstract type from which all generated protobuf structs extend.
	"""
	abstract type ProtoType end

	wiretypes(::Type{Int32})                            = [:int32, :sint32, :enum, :sfixed32]
	wiretypes(::Type{Int64})                            = [:int64, :sint64, :sfixed64]
	wiretypes(::Type{UInt32})                           = [:uint32, :fixed32]
	wiretypes(::Type{UInt64})                           = [:uint64, :fixed64]
	wiretypes(::Type{Bool})                             = [:bool]
	wiretypes(::Type{Float64})                          = [:double]
	wiretypes(::Type{Float32})                          = [:float]
	wiretypes(::Type{T}) where {T<:AbstractString}      = [:string]
	wiretypes(::Type{Vector{UInt8}})                    = [:bytes]
	wiretypes(::Type{Dict{K,V}}) where {K,V}            = [:map]
	wiretypes(::Type)                                   = [:obj]
	wiretypes(::Type{Vector{T}}) where {T}              = wiretypes(T)

	wiretype(::Type{T}) where {T}                       = wiretypes(T)[1]

	defaultval(::Type{T}) where {T<:Number}             = [zero(T)]
	defaultval(::Type{T}) where {T<:AbstractString}     = [convert(T,"")]
	defaultval(::Type{Bool})                            = [false]
	defaultval(::Type{Vector{T}}) where {T}             = Any[T[]]
	defaultval(::Type{Dict{K,V}}) where {K,V}           = [Dict{K,V}()]
	defaultval(::Type)                                  = []

	function _write_uleb(io::IO, x::T) where T <: Integer
		nw = 0
		cont = true
		while cont
			byte = x & MASK7
			if (x >>>= 7) != 0
				byte |= MSB
			else
				cont = false
			end
			nw += write(io, UInt8(byte))
		end
		nw
	end

	# max number of 7bit blocks for reading n bytes
	# d,r = divrem(sizeof(T)*8, 7)
	# (r > 0) && (d += 1)
	const _max_n = [2, 3, 4, 5, 6, 7, 8, 10]

	function _read_uleb_base(io::IO, ::Type{T}) where T <: Integer
		res = zero(T)
		n = 0
		byte = UInt8(MSB)
		while (byte & MSB) != 0
			byte = read(io, UInt8)
			res |= (convert(T, byte & MASK7) << (7*n))
			n += 1
		end
		n, res
	end

	function _read_uleb(io::IO, ::Type{Int32})
		n, res = _read_uleb_base(io, Int32)

		# negative int32 are encoded in 10 bytes (ref: https://developers.google.com/protocol-buffers/docs/encoding)
		# > if you use int32 or int64 as the type for a negative number, the resulting varint is always ten bytes long
		#
		# but Julia can be tolerant like the C protobuf implementation (unlike python)

		if n > _max_n[sizeof(res < 0 ? Int64 : Int32)]
			@debug("overflow reading Int32. returning 0")
			return Int32(0)
		end

		res
	end

	function _read_uleb(io::IO, ::Type{T}) where T <: Integer
		n, res = _read_uleb_base(io, T)
		# in case of overflow, consider it as missing field and return default value
		if n > _max_n[sizeof(T)]
			@debug("overflow reading integer type. returning 0", T)
			return zero(T)
		end
		res
	end

	function _write_zigzag(io::IO, x::T) where T <: Integer
		nbits = 8*sizeof(x)
		zx = (x << 1) ⊻ (x >> (nbits-1))
		_write_uleb(io, zx)
	end

	function _read_zigzag(io::IO, ::Type{T}) where T <: Integer
		zx = _read_uleb(io, UInt64)
		# result is positive if zx is even
		convert(T, iseven(zx) ? (zx >>> 1) : -signed((zx+1) >>> 1))
	end

	##
	# read and write field keys
	_write_key(io::IO, fld::Int, wiretyp::Int) = _write_uleb(io, (fld << 3) | wiretyp)
	function _read_key(io::IO)
		key = _read_uleb(io, UInt64)
		wiretyp = key & MASK3
		fld = key >>> 3
		(fld, wiretyp)
	end

	##
	# read and write field values
	write_varint(io::IO, x::T) where {T <: Integer} = _write_uleb(io, x)
	write_varint(io::IO, x::Int32) = _write_uleb(io, x < 0 ? Int64(x) : x)
	write_bool(io::IO, x::Bool) = _write_uleb(io, x ? 1 : 0)
	write_svarint(io::IO, x::T) where {T <: Integer} = _write_zigzag(io, x)

	read_varint(io::IO, ::Type{T}) where {T <: Integer} = _read_uleb(io, T)
	read_bool(io::IO) = Bool(_read_uleb(io, UInt64))
	read_bool(io::IO, ::Type{Bool}) = read_bool(io)
	read_svarint(io::IO, ::Type{T}) where {T <: Integer} = _read_zigzag(io, T)

	write_fixed(io::IO, x::UInt32) = _write_fixed(io, x)
	write_fixed(io::IO, x::UInt64) = _write_fixed(io, x)
	write_fixed(io::IO, x::Int32) = _write_fixed(io, reinterpret(UInt32, x))
	write_fixed(io::IO, x::Int64) = _write_fixed(io, reinterpret(UInt64, x))
	write_fixed(io::IO, x::Float32) = _write_fixed(io, reinterpret(UInt32, x))
	write_fixed(io::IO, x::Float64) = _write_fixed(io, reinterpret(UInt64, x))
	function _write_fixed(io::IO, ux::T) where T <: Unsigned
		N = sizeof(ux)
		for n in 1:N
			write(io, UInt8(ux & MASK8))
			ux >>>= 8
		end
		N
	end

	read_fixed(io::IO, typ::Type{UInt32}) = _read_fixed(io, convert(UInt32,0), 4)
	read_fixed(io::IO, typ::Type{UInt64}) = _read_fixed(io, convert(UInt64,0), 8)
	read_fixed(io::IO, typ::Type{Int32}) = reinterpret(Int32, _read_fixed(io, convert(UInt32,0), 4))
	read_fixed(io::IO, typ::Type{Int64}) = reinterpret(Int64, _read_fixed(io, convert(UInt64,0), 8))
	read_fixed(io::IO, typ::Type{Float32}) = reinterpret(Float32, _read_fixed(io, convert(UInt32,0), 4))
	read_fixed(io::IO, typ::Type{Float64}) = reinterpret(Float64, _read_fixed(io, convert(UInt64,0), 8))
	function _read_fixed(io::IO, ret::T, N::Int) where T <: Unsigned
		for n in 0:(N-1)
			byte = convert(T, read(io, UInt8))
			ret |= (byte << (8*n))
		end
		ret
	end

	function write_bytes(io::IO, data::Vector{UInt8})
		n = _write_uleb(io, sizeof(data))
		n += write(io, data)
		n
	end

	function read_bytes(io::IO)
		n = _read_uleb(io, UInt64)
		data = Vector{UInt8}(undef, n)
		read!(io, data)
		data
	end
	read_bytes(io::IO, ::Type{Vector{UInt8}}) = read_bytes(io)

	write_string(io::IO, x::AbstractString) = write_string(io, String(x))
	write_string(io::IO, x::String) = write_bytes(io, @static isdefined(Base, :codeunits) ? unsafe_wrap(Vector{UInt8}, x) : Vector{UInt8}(x))

	read_string(io::IO) = String(read_bytes(io))
	read_string(io::IO, ::Type{T}) where {T <: AbstractString} = convert(T, read_string(io))

	# TODO: wiretypes should become julia types, so that methods can be parameterized on them
	writeproto() = 0
	readproto() = nothing

	function write_map(io::IO, fldnum::Int, dict::Dict)
		dmeta = mapentry_meta(typeof(dict))
		iob = IOBuffer()

		n = 0
		for key in keys(dict)
			@debug("write_map", key)
			val = dict[key]
			writeproto(iob, key, dmeta.ordered[1])
			@debug("write_map", val)
			writeproto(iob, val, dmeta.ordered[2])
			n += _write_key(io, fldnum, WIRETYP_LENDELIM)
			n += write_bytes(io, take!(iob))
		end
		n
	end

	function read_map(io, dict::Dict{K,V}) where {K,V}
		iob = IOBuffer(read_bytes(io))

		dmeta = mapentry_meta(Dict{K,V})
		key_wtyp, key_wfn, key_rfn, key_jtyp = WIRETYPES[dmeta.numdict[1].ptyp]
		val_wtyp, val_wfn, val_rfn, val_jtyp = WIRETYPES[dmeta.numdict[2].ptyp]
		key_val = Vector{Union{K,V}}(undef, 2)

		while !eof(iob)
			fldnum, wiretyp = _read_key(iob)
			@debug("reading map", fldnum)

			fldnum = Int(fldnum)
			attrib = dmeta.numdict[fldnum]

			if fldnum == 1
				key_val[1] = read_field(iob, nothing, attrib, key_wtyp, K)
			elseif fldnum == 2
				key_val[2] = read_field(iob, nothing, attrib, val_wtyp, V)
			else
				skip_field(iob, wiretyp)
			end
		end
		@debug("read map", key=key_val[1], val=key_val[2])
		dict[key_val[1]] = key_val[2]
		dict
	end

	const WIRETYPES = Dict{Symbol,Tuple}(
		:int32          => (WIRETYP_VARINT,     write_varint,  read_varint,   Int32),
		:int64          => (WIRETYP_VARINT,     write_varint,  read_varint,   Int64),
		:uint32         => (WIRETYP_VARINT,     write_varint,  read_varint,   UInt32),
		:uint64         => (WIRETYP_VARINT,     write_varint,  read_varint,   UInt64),
		:sint32         => (WIRETYP_VARINT,     write_svarint, read_svarint,  Int32),
		:sint64         => (WIRETYP_VARINT,     write_svarint, read_svarint,  Int64),
		:bool           => (WIRETYP_VARINT,     write_bool,    read_bool,     Bool),
		:enum           => (WIRETYP_VARINT,     write_varint,  read_varint,   Int32),

		:fixed64        => (WIRETYP_64BIT,      write_fixed,   read_fixed,    UInt64),
		:sfixed64       => (WIRETYP_64BIT,      write_fixed,   read_fixed,    Int64),
		:double         => (WIRETYP_64BIT,      write_fixed,   read_fixed,    Float64),

		:string         => (WIRETYP_LENDELIM,   write_string,  read_string,   AbstractString),
		:bytes          => (WIRETYP_LENDELIM,   write_bytes,   read_bytes,    Vector{UInt8}),
		:obj            => (WIRETYP_LENDELIM,   writeproto,    readproto,     Any),
		:map            => (WIRETYP_LENDELIM,   write_map,     read_map,      Dict),

		:fixed32        => (WIRETYP_32BIT,      write_fixed,   read_fixed,    UInt32),
		:sfixed32       => (WIRETYP_32BIT,      write_fixed,   read_fixed,    Int32),
		:float          => (WIRETYP_32BIT,      write_fixed,   read_fixed,    Float32)
	)
end;

# ╔═╡ 43fe82c8-4c28-40f5-80d8-b19abd9e38f5
# this is a helper function to write to a temp buffer
function writeproto(x)
	io = IOBuffer()
	writeproto(io, x)
	take!(io)
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

# ╔═╡ ac0eb25e-9c83-4641-9afd-25881d59f2f0
begin
	io2 = IOBuffer()
	write(io2, target300) 
end

# ╔═╡ df50acc7-cd63-4a8d-b85b-cb458a7e06fe
read(io2, 2)

# ╔═╡ 3e9efab7-a666-43d2-99ce-fcae4e37f3a4
begin
	writex(x, ::Val{:uint32}) = "uint32 - $x"
	writex(x, ::Val{:uint64}) = "uint64 - $x"
	writex(x, ::Val{V}) where V = "unknown - $x"
end

# ╔═╡ 3812b4d8-863a-4f39-a78e-0f0f7d4ff8f1
# using this sort of Val pattern, we can move the type checking to use dispatch
begin
	fieldtype = :uint32
	[
		writex(55, Val(fieldtype)),
		writex(66, Val(:SomethingElse))
	]
end

# ╔═╡ 2238d1bb-2a54-4b27-8956-4863323ebc6a
md"""
# Serialization

This is a demonstration of proto serialization.  We assume a couple things:

1. We geneate immutable structs where each field is `Union{Missing, SomeType}`. This lets us treat all fields as optional and make the default value `missing`.
2. We generate a `writeproto` method for each struct which also takes in `IO`... this is just a bunch of code blocks (one for each field) that writes a key and then does field-specific serialization.
"""

# ╔═╡ fd3de1a2-28e3-4ddb-a9b1-ba358d7ba5c5
# TODO use generated functions here
begin
	writefield(io::IO, idx::Int64, val, ::Val{:uint32}) = writefield(io, idx, val, WIRETYPES[:uint32]...)
	writefield(io::IO, idx::Int64, val, ::Val{:string}) = writefield(io, idx, val, WIRETYPES[:string]...)
	
	# fallback for all others
	# function writefield(io::IO, idx::Int64, val, ::Val{T}) where T
	# 	writefield(io, idx, val, WIRETYP_LENDELIM, writeproto, readproto, typeof(val))
	# end
end

# ╔═╡ 60748857-3b38-48ef-8dc3-5da3bb06515a
function writefield(io::IO, idx::Int64, val, wiretype, writefn, readfn, T)
	n = 0
	n += _write_key(io, idx, wiretype)
	n += writefn(io, val)
	n
end

# ╔═╡ 777d3098-1fed-4d7e-b8c3-a5896ee30c3e
# suppose this is the generated struct for a message with 2 fields
struct XXX
	f1::Union{Missing, UInt32} # uint32 f1 = 1;
	f2::Union{Missing, String} # string f2 = 2;
end

# ╔═╡ 4cacfe92-665b-4a6d-b33c-d6d780e20a1a
# then this is the serialization
function writeproto(io::IO, x::XXX)
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

# ╔═╡ cf186cb3-6395-4e8c-aa4e-3cc5ecd4d6d1
struct ZZZ
	x::Union{Missing, XXX} # XXX x = 3;
end

# ╔═╡ 83d54da3-ff87-41be-ae67-118684aad6b2
# TODO this should be generated code
function writeproto(io::IO, z::ZZZ)
	n = 0
	
	# this is a generated block for a nested proto (i.e. non-primitive).
	# as you can see we will let dispatch handle the complexity of it...
	# this code is pretty generic.
	if !ismissing(z.x)
		n += _write_key(io, 3, WIRETYP_LENDELIM)
		# write the nested proto to a temp buffer,
		# then write then length as a varint and then the raw bytes
		bytes = writeproto(z.x)
		n += _write_uleb(io, length(bytes))
		n += write(io, bytes)
	end
	
	n
end

# ╔═╡ 310a528b-5056-46e3-8525-4649d32e6ef0
# should be 0x08 0x96 0x01
writeproto(x)

# ╔═╡ 35245834-c4f2-446a-ba23-7866db85833f
writeproto(y)

# ╔═╡ 8015df0d-13d2-4912-814b-8bdc70904653
writeproto(ZZZ(XXX(150, missing)))

# ╔═╡ 000447d3-45e6-4e16-a3e8-0f5b12fcf9ef
md"""
# Deserialization

Similar to serialization, we need to generate a constructor `MyMessage(io::IO)`... i.e. a method which takes an IO stream and constructs the julia object from it.
"""

# ╔═╡ 3127f08e-d7bf-4b50-a516-719634b44046
# TODO use generated functions here
begin
	readfield(io::IO, ::Val{:uint32}) = readfield(io, WIRETYPES[:uint32]...)
	readfield(io::IO, ::Val{:string}) = readfield(io, WIRETYPES[:string]...)
	
	# fallback for all others
	# function writefield(io::IO, idx::Int64, val, ::Val{T}) where T
	# 	writefield(io, idx, val, WIRETYP_LENDELIM, writeproto, readproto, typeof(val))
	# end
end

# ╔═╡ e2c93b2e-bfa7-44cd-bd10-1a5dcaa876a0
function readfield(io::IO, wiretype, writefn, readfn, ::Type{T}) where T
	readfn(io, T)
end

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


# ╔═╡ Cell order:
# ╠═7dc6f22a-4405-43b6-8d54-adc57f9c934f
# ╠═43fe82c8-4c28-40f5-80d8-b19abd9e38f5
# ╠═81d7c2e7-6eeb-4d01-a183-1b6e669d0d7d
# ╠═e8744639-d84c-4a82-8211-5c64fcd6c416
# ╠═e5b8f286-ab63-4e33-ba40-74793d8fda94
# ╠═398dcf24-a03c-49be-a98b-54d6ad91b802
# ╠═5455261f-0838-49cf-9327-1b76793f1930
# ╟─38c1160a-ba01-4a05-b226-6ca82ff7147b
# ╟─bbd33f3d-27d6-483e-b3d5-b298968a952b
# ╠═5a0b5e21-8867-4aab-8a41-1a1bc0f2b103
# ╠═37a46a78-0e82-4543-8584-8cab5a104292
# ╠═ac0eb25e-9c83-4641-9afd-25881d59f2f0
# ╠═df50acc7-cd63-4a8d-b85b-cb458a7e06fe
# ╠═3e9efab7-a666-43d2-99ce-fcae4e37f3a4
# ╠═3812b4d8-863a-4f39-a78e-0f0f7d4ff8f1
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
