proto_default(::Type) = missing
proto_default(::Type{T}) where {T<:Number} = zero(T)
proto_default(::Type{T}) where {T<:AbstractString} = ""
proto_default(::Type{Bool}) = false
proto_default(::Type{Vector{T}}) where T = T[]
