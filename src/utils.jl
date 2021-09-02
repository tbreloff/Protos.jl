proto_default(::Type) = missing
proto_default(::Type{T}) where {T<:Number} = zero(T)
proto_default(::Type{T}) where {T<:AbstractString} = ""
proto_default(::Type{Bool}) = false
proto_default(::Type{Vector{T}}) where T = T[]


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

# some string macros for diffent sizes of UInts

macro frombits8_str(s)
    frombits_str(s, UInt8)
end

macro frombits64_str(s)
    frombits_str(s, UInt64)
end