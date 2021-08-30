
# varints
# https://developers.google.com/protocol-buffers/docs/encoding#varints

function serialize_varint(i::Integer)

end

# a byte in a varint uses the first bit to signal whether there's more varint bytes following this one
more_varint_to_come(byte::UInt8) = byte >> 7

# get the rightmost 7 bits as a UInt8
get_seven_bits(i::Integer) = UInt8((~zero(UInt8) >> 1) & i)