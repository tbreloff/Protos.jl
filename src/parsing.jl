
"""
The Parsing module handles the translation from `.proto` file text into
NamedTuples which contain the parsed content.
The `parse_proto` method maps either text or IO to a nested NamedTuple.
"""
module Parsing

using CombinedParsers
using CombinedParsers.Regexp: whitespace, whitespace_newline

export parse_proto

# a period
period = CharIn('.')

# optional whitespace
ws = Optional(whitespace)

# equals sign with optional surrounding whitespace
_equals = ws * "=" * ws

# handle parsers separated by commas and whitespace
function commasep(x, delim=','*ws)
    join(Repeat(x), delim, infix=:prefix) do (x1, xrest)
        ret = Any[]
        push!(ret, x1)
        for xi in xrest
            push!(ret, xi[2])
        end
        ret
    end
end

# letters and digits
letter = CharIn('A':'Z', 'a':'z')
decimalDigit = CharIn('0':'9')
octalDigit = CharIn('0':'7')
hexDigit = CharIn('0':'9', 'A':'F', 'a':'f')
letterExtended = Either{Any}(letter, decimalDigit, CharIn('_'))

ident = !(letter * Repeat(letterExtended))
fullIdent = !(ident * Repeat(period * ident))
messageName = ident
enumName = ident
fieldName = ident
oneofName = ident
mapName = ident
serviceName = ident
rpcName = ident
messageType = !(Optional(period) * Repeat(ident * period) * messageName)
enumType = messageType

# integer literals
decimalLit = CharIn('1':'9') * Repeat(decimalDigit)
octalLit = CharIn('0') * Repeat(octalDigit)
hexLit = CharIn('0') * CharIn("xX") * Repeat1(hexDigit)
intLit = !Either{Any}(decimalLit, octalLit, hexLit)

# floating point literals
decimals = Repeat1(decimalDigit)
exponent = CharIn("eE") * Optional(CharIn("+-")) * decimals
floatLit = !Either{Any}(
    decimals * period * Optional(decimals) * Optional(exponent),
    decimals * exponent,
    period * decimals * Optional(exponent)
)

# boolean
boolLit = !Either{Any}("true", "false")

# string literals
# hexEscape = '\\' * CharIn("xX") * hexDigit * hexDigit
# octEscape = '\\' * Repeat(3, 3, octalDigit)
# charEscape = CharIn("\a\b\f\n\r\t\v\\\'\"")
# charValue = hexEscape | octEscape | charEscape | CharIn("\0\n\\")
charValue = AnyChar()
_quote = CharIn("'", '"')
strLit = Either{Any}(
    Sequence(2, "'", !Repeat(charValue), "'"),
    Sequence(2, '"', !Repeat(charValue), '"')
)

# empty statement
emptyStatement = ";";

# comments
blockComment = Sequence(2,
    "/*", !Repeat(AnyChar()), "*/"
)
lineComment = Sequence(2,
    "//", !Repeat(CharNotIn("\n\r")), "\n"
)
lineComments = map(lineComment * Repeat(Optional(whitespace_newline) * lineComment)) do (c1, cRest)
    # make one big comment from the multiple line comments
    comms = cat([c1], [ci[2] for ci in cRest], dims=1)
    join(comms, "\n")
end

# this grabs a comment block with any whitespace before or after.
# we'll use this in most places we want to grab comments.
filler = Sequence(2,
    Optional(whitespace_newline),
    Optional(Either{Any}(blockComment, lineComments)),
    Optional(whitespace_newline)
)

# constant
constant = Either{Any}(
	fullIdent,
	Optional(CharIn("+-")) * intLit,
	Optional(CharIn("+-")) * floatLit,
	strLit,
	boolLit
);

# syntax to define proto version
# example:   syntax="proto3";
syntax = !("syntax" * _equals * _quote * "proto3" * _quote * ";");

# import statement
# example: import public "other.proto";
_import = Sequence(
	"import", whitespace, 
	:mod=>Optional(Sequence(1, Either("weak", "public"), whitespace)),
	:path=>strLit, ";"
);

# package statement
# example: package foo.bar;
_package = Sequence(
	"package", whitespace, :package=>fullIdent, ";"
);

# option statement
# example:  option java_package = "com.example.foo";
optionName = !Sequence(
    Either{Any}(ident, "(" * fullIdent * ")"),
    Repeat(period * ident)
)
_option = Sequence(
    :comments=>filler,
    "option", whitespace,
    :key=>optionName, _equals, :value=>constant, ";"
)

# fields
fieldType = !Either{Any}(
    "double", "float", "int32", "int64", "uint32", "uint64",
    "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64",
    "bool", "string", "bytes", messageType, enumType
)
# get the intLit as an Int64
fieldNumber = map(i -> parse(Int64, i), intLit)
fieldOption = Sequence(:name=>optionName, _equals, :val=>constant)
fieldOptions = fieldOption * Repeat("," * ws * fieldOption)
fieldMaybeOptions = Sequence(2, 
    ws,
    Optional(Sequence(2, '[', fieldOptions, ']')), 
    ';'
)
field = Sequence(
    Optional("repeated" * whitespace),
    :type=>fieldType, whitespace,
    :name=>fieldName, _equals, :num=>fieldNumber, 
    fieldMaybeOptions
)


# oneofs
oneofField = Sequence(
    :type=>fieldType, whitespace,
    :name=>fieldName, _equals, :num=>fieldNumber, 
    fieldMaybeOptions
)
oneofFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(_option, oneofField, emptyStatement)
)
oneof = Sequence(
    :comments=>filler,
    "oneof", whitespace, :oneofName=>oneofName, ws, '{',
    :fields=>Repeat(oneofFieldWithComments),
    filler, '}'
)

# maps
keyType = Either(
    "int32", "int64', uint32", "unit64", "sint32", "sint64",
    "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string"
)
mapField = Sequence(
    "map", ws, "<",
    :keyType=>keyType,
    ",", ws,
    :valueType=>fieldType,
    ">", ws,
    :name=>mapName, _equals, :num=>fieldNumber, 
    fieldMaybeOptions
)

# reserved statements
# example: reserved 2, 15, 9 to 11;
# example: reserved "foo", "bar";
fieldNames = commasep(fieldName)
range = Either{Any}(
    !Sequence(intLit, " to ", intLit | "max"),
    intLit
)
ranges = commasep(range)
reserved = Sequence(
    "reserved", whitespace, :reserved=>Either{Any}(ranges, fieldNames)
)

# enums
# example:
#	enum XX {
#		option allow_alias = true;
#		UNKNOWN = 0;
#	}
enumValueOption = optionName * _equals * constant
enumField = Sequence(
    :fieldname=>ident, _equals, 
    :fieldnum=>map(i -> parse(Int64, i), !Sequence(Optional('-'), intLit)),
    Optional(Sequence('[', enumValueOption, 
            Repeat(Sequence(',', ws, enumValueOption)), ']')), ';'
)
enumFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(_option, enumField, emptyStatement)
)
enum = Sequence(
    :comments=>filler,
    "enum", whitespace, :enumName=>enumName, ws, '{', 
    :fields=>Repeat(enumFieldWithComments),
    filler,
    '}'
)

# message definitions
innerFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(field, _option, oneof, mapField, reserved, emptyStatement)
)
innerMessage = Sequence(
    :comments=>filler,
    "message", whitespace, :messageName=>messageName, ws, 
    '{',
    :fields=>Repeat(innerFieldWithComments),
    filler,
    '}'
)
messageFieldWithComments = Either{Any}(
    innerMessage,
    enum,
    innerFieldWithComments
)
# Sequence(
#     :comments=>filler,
#     :field=>Either{Any}(field, enum, _option, oneof, mapField, reserved, emptyStatement, innerMessage)
# )
message = Sequence(
    :comments=>filler,
    "message", whitespace, :messageName=>messageName, ws, 
    '{',
    :fields=>Repeat(messageFieldWithComments),
    filler,
    '}'
)

# service definitions

# returns true when matching "stream "
isstream = map(x -> x=="stream ", Optional("stream "))

rpc = Sequence(
    :comments=>filler,
    "rpc", whitespace, 
    :rpcName=>rpcName, ws, 
    '(', :inputIsStream=>isstream, :inputType=>messageType, ')',
    whitespace, "returns", whitespace,
    '(', :outputIsStream=>isstream, :outputType=>messageType, ')',
    ws, Either{Any}(
        Sequence('{', :extra=>Optional(_option | emptyStatement), "};"),
        ';'
    )
)

service = Sequence(
    :comments=>filler,
    "service", whitespace, :serviceName=>serviceName, ws, '{', 
    :rpcs=>Repeat(Sequence(2, whitespace_newline, Either{Any}(_option, rpc, emptyStatement))),
    whitespace_newline, '}'
)

# a complete proto file
topLevelDef = Either{Any}(message, enum, service)
proto = Sequence(
    :comment=>filler,
    syntax,
    :statements=>Repeat(Sequence(2, 
        whitespace_newline, 
        Either{Any}(_import, _package, _option, topLevelDef, emptyStatement)
    )),
    filler,
    :unparsed=>!Repeat(AnyChar()) # anything we missed
)

function parse_proto(text::AbstractString)
    proto(text)
end

function parse_proto(io::IO)
    text = read(io, String)
    parse_proto(text)
end

end # module
