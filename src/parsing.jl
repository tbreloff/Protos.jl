using CombinedParsers
using CombinedParsers.Regexp: whitespace, whitespace_newline

export parse_proto

# a period
const period = CharIn('.')

# optional whitespace
const ws = Optional(whitespace)

# equals sign with optional surrounding whitespace
const _equals = ws * "=" * ws

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
const letter = CharIn('A':'Z', 'a':'z')
const decimalDigit = CharIn('0':'9')
const octalDigit = CharIn('0':'7')
const hexDigit = CharIn('0':'9', 'A':'F', 'a':'f')
const letterExtended = Either{Any}(letter, decimalDigit, CharIn('_'))

const ident = !(letter * Repeat(letterExtended))
const fullIdent = !(ident * Repeat(period * ident))
const messageName = ident
const enumName = ident
const fieldName = ident
const oneofName = ident
const mapName = ident
const serviceName = ident
const rpcName = ident
const messageType = !(Optional(period) * Repeat(ident * period) * messageName)
const enumType = messageType

# integer literals
const decimalLit = CharIn('1':'9') * Repeat(decimalDigit)
const octalLit = CharIn('0') * Repeat(octalDigit)
const hexLit = CharIn('0') * CharIn("xX") * Repeat1(hexDigit)
const intLit = !Either{Any}(decimalLit, octalLit, hexLit)

# floating point literals
const decimals = Repeat1(decimalDigit)
const exponent = CharIn("eE") * Optional(CharIn("+-")) * decimals
const floatLit = !Either{Any}(
    decimals * period * Optional(decimals) * Optional(exponent),
    decimals * exponent,
    period * decimals * Optional(exponent)
)

# boolean
const boolLit = !Either{Any}("true", "false")

# string literals
# hexEscape = '\\' * CharIn("xX") * hexDigit * hexDigit
# octEscape = '\\' * Repeat(3, 3, octalDigit)
# charEscape = CharIn("\a\b\f\n\r\t\v\\\'\"")
# charValue = hexEscape | octEscape | charEscape | CharIn("\0\n\\")
const charValue = AnyChar()
const _quote = CharIn("'", '"')
const strLit = Either{Any}(
    Sequence(2, "'", !Repeat(charValue), "'"),
    Sequence(2, '"', !Repeat(charValue), '"')
)

# empty statement
const emptyStatement = ";";

# comments
const blockComment = Sequence(2,
    "/*", !Repeat(AnyChar()), "*/"
)
const lineComment = Sequence(2,
    "//", !Repeat(CharNotIn("\n\r")), "\n"
)
const lineComments = map(lineComment * Repeat(Optional(whitespace_newline) * lineComment)) do (c1, cRest)
    # make one big comment from the multiple line comments
    comms = cat([c1], [ci[2] for ci in cRest], dims=1)
    join(comms, "\n")
end

# this grabs a comment block with any whitespace before or after.
# we'll use this in most places we want to grab comments.
const filler = Sequence(2,
    Optional(whitespace_newline),
    Optional(Either{Any}(blockComment, lineComments)),
    Optional(whitespace_newline)
)

# constant
const constant = Either{Any}(
	fullIdent,
	Optional(CharIn("+-")) * intLit,
	Optional(CharIn("+-")) * floatLit,
	strLit,
	boolLit
);

# syntax to define proto version
# example:   syntax="proto3";
const syntax = !("syntax" * _equals * _quote * "proto3" * _quote * ";");

# import statement
# example: import public "other.proto";
const _import = Sequence(
	"import", whitespace, 
	:mod=>Optional(Sequence(1, Either("weak", "public"), whitespace)),
	:path=>strLit, ";"
);

# package statement
# example: package foo.bar;
const _package = Sequence(
	"package", whitespace, :package=>fullIdent, ";"
);

# option statement
# example:  option java_package = "com.example.foo";
const optionName = !Sequence(
    Either{Any}(ident, "(" * fullIdent * ")"),
    Repeat(period * ident)
)
const _option = Sequence(
    "option", whitespace,
    :key=>optionName, _equals, :value=>constant, ";"
)

# fields
const fieldType = !Either{Any}(
    "double", "float", "int32", "int64", "uint32", "uint64",
    "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64",
    "bool", "string", "bytes", messageType, enumType
)
# get the intLit as an Int64
const fieldNumber = map(i -> parse(Int64, i), intLit)
const fieldOption = Sequence(:name=>optionName, _equals, :val=>constant)
const fieldOptions = fieldOption * Repeat("," * ws * fieldOption)
const fieldMaybeOptions = Sequence(2, 
    ws,
    Optional(Sequence(2, '[', fieldOptions, ']')), 
    ';'
)
const field = Sequence(
    Optional("repeated" * whitespace),
    :type=>fieldType, whitespace,
    :name=>fieldName, _equals, :num=>fieldNumber, 
    fieldMaybeOptions
)


# oneofs
const oneofField = Sequence(
    :type=>fieldType, whitespace,
    :name=>fieldName, _equals, :num=>fieldNumber, 
    fieldMaybeOptions
)
const oneofFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(_option, oneofField, emptyStatement)
)
const oneof = Sequence(
    :comments=>filler,
    "oneof", whitespace, :name=>oneofName, ws, '{',
    :fields=>Repeat(oneofFieldWithComments),
    filler, '}'
)

# maps
const keyType = Either(
    "int32", "int64', uint32", "unit64", "sint32", "sint64",
    "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string"
)
const mapField = Sequence(
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
const fieldNames = commasep(fieldName)
const range = Either{Any}(
    !Sequence(intLit, " to ", intLit | "max"),
    intLit
)
const ranges = commasep(range)
const reserved = Sequence(3,
    "reserved", whitespace, ranges | fieldNames
)

# enums
# example:
#	enum XX {
#		option allow_alias = true;
#		UNKNOWN = 0;
#	}
const enumValueOption = optionName * _equals * constant
const enumField = Sequence(
    :fieldname=>ident, _equals, 
    :fieldnum=>map(i -> parse(Int64, i), !Sequence(Optional('-'), intLit)),
    Optional(Sequence('[', enumValueOption, 
            Repeat(Sequence(',', ws, enumValueOption)), ']')), ';'
)
const enumFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(_option, enumField, emptyStatement)
)
const enum = Sequence(
    :comments=>filler,
    "enum", whitespace, :name=>enumName, ws, '{', 
    :fields=>Repeat(enumFieldWithComments),
    filler,
    '}'
)

# message definitions
const innerFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(field, enum, _option, oneof, mapField, reserved, emptyStatement)
)
const innerMessage = Sequence(
    :comments=>filler,
    "message", whitespace, :messageName=>messageName, ws, 
    '{',
    :fields=>Repeat(innerFieldWithComments),
    filler,
    '}'
)
const messageFieldWithComments = Sequence(
    :comments=>filler,
    :field=>Either{Any}(field, enum, _option, oneof, mapField, reserved, emptyStatement, innerMessage)
)
const message = Sequence(
    :comments=>filler,
    "message", whitespace, :messageName=>messageName, ws, 
    '{',
    :fields=>Repeat(innerFieldWithComments),
    filler,
    '}'
)

# service definitions

# returns true when matching "stream "
const isstream = map(x -> x=="stream ", Optional("stream "))

const rpc = Sequence(
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

const service = Sequence(
    :comments=>filler,
    "service", whitespace, :serviceName=>serviceName, ws, '{', 
    :rpcs=>Repeat(Sequence(2, whitespace_newline, Either{Any}(_option, rpc, emptyStatement))),
    whitespace_newline, '}'
)

# a complete proto file
const topLevelDef = Either{Any}(message, enum, service)
const proto = Sequence(
    :comment=>filler,
    syntax,
    :statements=>Repeat(Sequence(2, 
        whitespace_newline, 
        Either{Any}(_import, _package, _option, topLevelDef, emptyStatement)
    )),
    filler
)

function parse_proto(text::AbstractString)
    proto(text)
end

function parse_proto(io::IO)
    text = read(io, String)
    parse_proto(text)
end
