
#--------------------------------------------------------------------
# Note: some of this code was copied/adapted from JuliaIO/ProtoBuf.jl which has the following license:
# 
#   The ProtoBuf.jl package is licensed under the MIT "Expat" License:
#
#   Copyright (c) 2014: Tanmay Mohapatra.
#
#   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
#   documentation files (the "Software"), to deal in the Software without restriction, including without limitation 
#   the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and 
#   to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
#   TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
#   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF 
#   CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#--------------------------------------------------------------------

module Serialization

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
abstract type Proto end

proto_types(::Type{Int32})                            = [:int32, :sint32, :enum, :sfixed32]
proto_types(::Type{Int64})                            = [:int64, :sint64, :sfixed64]
proto_types(::Type{UInt32})                           = [:uint32, :fixed32]
proto_types(::Type{UInt64})                           = [:uint64, :fixed64]
proto_types(::Type{Bool})                             = [:bool]
proto_types(::Type{Float64})                          = [:double]
proto_types(::Type{Float32})                          = [:float]
proto_types(::Type{T}) where {T<:AbstractString}      = [:string]
proto_types(::Type{Vector{UInt8}})                    = [:bytes]
proto_types(::Type{Dict{K,V}}) where {K,V}            = [:map]
proto_types(::Type)                                   = [:obj]
proto_types(::Type{Vector{T}}) where {T}              = proto_types(T)

proto_type(::Type{T}) where {T}                       = proto_types(T)[1]


const WIRETYPES = Dict{Symbol, Int64}(
    :int32          => WIRETYP_VARINT,
    :int64          => WIRETYP_VARINT,
    :uint32         => WIRETYP_VARINT,
    :uint64         => WIRETYP_VARINT,
    :sint32         => WIRETYP_VARINT,
    :sint64         => WIRETYP_VARINT,
    :bool           => WIRETYP_VARINT,
    :enum           => WIRETYP_VARINT,
    :fixed64        => WIRETYP_64BIT,
    :sfixed64       => WIRETYP_64BIT,
    :double         => WIRETYP_64BIT,
    :string         => WIRETYP_LENDELIM,
    :bytes          => WIRETYP_LENDELIM,
    :map            => WIRETYP_LENDELIM,
    :fixed32        => WIRETYP_32BIT,
    :sfixed32       => WIRETYP_32BIT,
    :float          => WIRETYP_32BIT
)

wiretype(s::AbstractString) = wiretype(Symbol(s))
wiretype(s::Symbol) = haskey(WIRETYPES, s) ? WIRETYPES[s] : WIRETYP_LENDELIM

const JTYPES = Dict{Symbol, DataType}(
    :int32    => Int32,
    :int64    => Int64,
    :uint32   => UInt32,
    :uint64   => UInt64,
    :sint32   => Int32,
    :sint64   => Int64,
    :bool     => Bool,
    :enum     => Int32,
    :fixed64  => UInt64,
    :sfixed64 => Int64,
    :double   => Float64,
    :string   => AbstractString,
    :bytes    => Vector{UInt8},
    # :map      => Dict,
    :fixed32  => UInt32,
    :sfixed32 => Int32,
    :float    => Float32
)

# TODO: this should return the DataType associated with the type symbol in the proto file
proto_jtype(::Symbol) = Missing

jtype(::Missing) = Missing
jtype(s::AbstractString) = jtype(Symbol(s))
jtype(s::Symbol) = haskey(JTYPES, s) ? JTYPES[s] : proto_jtype(s)

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

# const WIRETYPES = Dict{Symbol,Tuple}(
#     :int32          => (WIRETYP_VARINT,     write_varint,  read_varint,   Int32),
#     :int64          => (WIRETYP_VARINT,     write_varint,  read_varint,   Int64),
#     :uint32         => (WIRETYP_VARINT,     write_varint,  read_varint,   UInt32),
#     :uint64         => (WIRETYP_VARINT,     write_varint,  read_varint,   UInt64),
#     :sint32         => (WIRETYP_VARINT,     write_svarint, read_svarint,  Int32),
#     :sint64         => (WIRETYP_VARINT,     write_svarint, read_svarint,  Int64),
#     :bool           => (WIRETYP_VARINT,     write_bool,    read_bool,     Bool),
#     :enum           => (WIRETYP_VARINT,     write_varint,  read_varint,   Int32),

#     :fixed64        => (WIRETYP_64BIT,      write_fixed,   read_fixed,    UInt64),
#     :sfixed64       => (WIRETYP_64BIT,      write_fixed,   read_fixed,    Int64),
#     :double         => (WIRETYP_64BIT,      write_fixed,   read_fixed,    Float64),

#     :string         => (WIRETYP_LENDELIM,   write_string,  read_string,   AbstractString),
#     :bytes          => (WIRETYP_LENDELIM,   write_bytes,   read_bytes,    Vector{UInt8}),
#     # :obj            => (WIRETYP_LENDELIM,   writeproto,    readproto,     Any),
#     :map            => (WIRETYP_LENDELIM,   write_map,     read_map,      Dict),

#     :fixed32        => (WIRETYP_32BIT,      write_fixed,   read_fixed,    UInt32),
#     :sfixed32       => (WIRETYP_32BIT,      write_fixed,   read_fixed,    Int32),
#     :float          => (WIRETYP_32BIT,      write_fixed,   read_fixed,    Float32)
# )




writefield(io::IO, idx::Int64, val, ::Val{:int32})    = writefield(io, idx, val, WIRETYP_VARINT,     write_varint)
writefield(io::IO, idx::Int64, val, ::Val{:int64})    = writefield(io, idx, val, WIRETYP_VARINT,     write_varint)
writefield(io::IO, idx::Int64, val, ::Val{:uint32})   = writefield(io, idx, val, WIRETYP_VARINT,     write_varint)
writefield(io::IO, idx::Int64, val, ::Val{:uint64})   = writefield(io, idx, val, WIRETYP_VARINT,     write_varint)
writefield(io::IO, idx::Int64, val, ::Val{:sint32})   = writefield(io, idx, val, WIRETYP_VARINT,     write_svarint)
writefield(io::IO, idx::Int64, val, ::Val{:sint64})   = writefield(io, idx, val, WIRETYP_VARINT,     write_svarint)
writefield(io::IO, idx::Int64, val, ::Val{:bool})     = writefield(io, idx, val, WIRETYP_VARINT,     write_bool)
writefield(io::IO, idx::Int64, val, ::Val{:enum})     = writefield(io, idx, val, WIRETYP_VARINT,     write_varint)

writefield(io::IO, idx::Int64, val, ::Val{:fixed64})  = writefield(io, idx, val, WIRETYP_64BIT,      write_fixed)
writefield(io::IO, idx::Int64, val, ::Val{:sfixed64}) = writefield(io, idx, val, WIRETYP_64BIT,      write_fixed)
writefield(io::IO, idx::Int64, val, ::Val{:double})   = writefield(io, idx, val, WIRETYP_64BIT,      write_fixed)

writefield(io::IO, idx::Int64, val, ::Val{:string})   = writefield(io, idx, val, WIRETYP_LENDELIM,   write_string)
writefield(io::IO, idx::Int64, val, ::Val{:bytes})    = writefield(io, idx, val, WIRETYP_LENDELIM,   write_bytes)
# writefield(io::IO, idx::Int64, val, ::Val{:obj})      = writefield(io, idx, val, WIRETYP_LENDELIM,   writeproto)
writefield(io::IO, idx::Int64, val, ::Val{:map})      = writefield(io, idx, val, WIRETYP_LENDELIM,   write_map)

writefield(io::IO, idx::Int64, val, ::Val{:fixed32})  = writefield(io, idx, val, WIRETYP_32BIT,      write_fixed)
writefield(io::IO, idx::Int64, val, ::Val{:sfixed32}) = writefield(io, idx, val, WIRETYP_32BIT,      write_fixed)
writefield(io::IO, idx::Int64, val, ::Val{:float})    = writefield(io, idx, val, WIRETYP_32BIT,      write_fixed)


function writefield(io::IO, idx::Int64, val, wiretype::Int64, writefn::Function)
	n = 0
	n += _write_key(io, idx, wiretype)
	n += writefn(io, val)
	n
end

"""
This serializes a Proto object to an IOStream.
"""
function writeproto end

# this is a helper function to write to a temp buffer
function writeproto(x)
	io = IOBuffer()
	writeproto(io, x)
	take!(io)
end


readfield(io::IO, ::Val{:int32})    = read_varint(io, Int32)
readfield(io::IO, ::Val{:int64})    = read_varint(io, Int64)
readfield(io::IO, ::Val{:uint32})   = read_varint(io, UInt32)
readfield(io::IO, ::Val{:uint64})   = read_varint(io, UInt64)
readfield(io::IO, ::Val{:sint32})   = read_svarint(io, Int32)
readfield(io::IO, ::Val{:sint64})   = read_svarint(io, Int64)
readfield(io::IO, ::Val{:bool})     = read_bool(io, Bool)
readfield(io::IO, ::Val{:enum})     = read_varint(io, Int32)

readfield(io::IO, ::Val{:fixed64})  = read_fixed(io, UInt64)
readfield(io::IO, ::Val{:sfixed64}) = read_fixed(io, Int64)
readfield(io::IO, ::Val{:double})   = read_fixed(io, Float64)

readfield(io::IO, ::Val{:string})   = read_string(io, AbstractString)
readfield(io::IO, ::Val{:bytes})    = read_bytes(io, Vector{UInt8})
# readfield(io::IO, ::Val{:obj})      = readproto(io, Any)
readfield(io::IO, ::Val{:map})      = read_map(io, Dict)

readfield(io::IO, ::Val{:fixed32})  = read_fixed(io, UInt32)
readfield(io::IO, ::Val{:sfixed32}) = read_fixed(io, Int32)
readfield(io::IO, ::Val{:float})    = read_fixed(io, Float32)

end # module
