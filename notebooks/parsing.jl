### A Pluto.jl notebook ###
# v0.15.1

using Markdown
using InteractiveUtils

# ╔═╡ 381e09a0-f243-11eb-2bf8-99677165e439
using CombinedParsers

# ╔═╡ c5ff4ddd-0c52-45e3-bd24-808b4a61ac9f
using CombinedParsers.Regexp: whitespace

# ╔═╡ ba772876-a0a5-46b1-83e0-e92236567df5
md"""
# ProtoBuf v3 Spec
"""

# ╔═╡ 1d155e37-26d3-47c5-961c-8575b37cf525
# helpers
begin
	period = CharIn('.')
	ws = Optional(whitespace)
	_equals = ws * "=" * ws
end;

# ╔═╡ a9e631f8-f21e-4802-823e-f4742c8eb1d8
# letters and digits
begin
	letter = CharIn('A':'Z', 'a':'z')
	decimalDigit = CharIn('0':'9')
	octalDigit = CharIn('0':'7')
	hexDigit = CharIn('0':'9', 'A':'F', 'a':'f')
end;

# ╔═╡ c43e4f2e-4f4a-4d07-8864-36d1abee1cac
# identifiers
begin
	ident = !(letter * Repeat(letter | decimalDigit | CharIn('_')))
	fullIdent = ident * Repeat(period * ident)
	messageName = ident
	enumName = ident
	fieldName = ident
	oneofName = ident
	mapName = ident
	serviceName = ident
	rpcName = ident
	messageType = !(Optional(period) * Repeat(ident * period) * messageName)
	enumType = messageType
end;

# ╔═╡ 0aeacc7d-8ccc-48ab-950c-dc49d9e05daa
# get the structured parse results
messageType("fdkjs.df")

# ╔═╡ 1958eaef-fb25-4b85-aa91-3c251d17ae89
# get the matched string
(!messageType)("fdkjs.df")

# ╔═╡ 1f0d70fd-e924-4053-9bf6-42e4c69a64f6
# integer literals
begin
	decimalLit = CharIn('1':'9') * Repeat(decimalDigit)
	octalLit = CharIn('0') * Repeat(octalDigit)
	hexLit = CharIn('0') * CharIn("xX") * Repeat1(hexDigit)
	intLit = !(decimalLit | octalLit | hexLit)
end;

# ╔═╡ e650f905-f867-4011-a995-265f08bfddd0
# floating point literals
begin
	decimals = Repeat1(decimalDigit)
	exponent = CharIn("eE") * Optional(CharIn("+-")) * decimals
	floatLit = !Either(
		decimals * period * Optional(decimals) * Optional(exponent),
		decimals * exponent,
		period * decimals * Optional(exponent)
	)
end;

# ╔═╡ 8f83eb51-6ffe-4059-a871-9bc72f6eefe4
# boolean
boolLit = !Either("true", "false")

# ╔═╡ c6f30865-c82f-43c1-a406-c789542cced1
floatLit("3.4e32")

# ╔═╡ e2b67ef1-8c9b-4c1f-a217-1b860a7c7fbf
boolLit("true")

# ╔═╡ 7b05dbdd-dfc2-4ad1-9811-285f7f7a20c7
# string literals
begin
	hexEscape = '\\' * CharIn("xX") * hexDigit * hexDigit
	octEscape = '\\' * Repeat(3, 3, octalDigit)
	charEscape = CharIn("\a\b\f\n\r\t\v\\\'\"")
	charValue = hexEscape | octEscape | charEscape | CharIn("\0\n\\")
	_quote = CharIn("'", '"')
	strLit = !Either(
		"'" * Repeat(charValue) * "'",
		'"' * Repeat(charValue) * '"'
	)
end;

# ╔═╡ db8069fb-c088-4421-97ba-6beedeb16f81
charValue(raw"\231")

# ╔═╡ 67fdaab4-beed-4d93-b7a3-d0f93aa6dece
CharIn('"', "'")(raw"'")

# ╔═╡ eac881c7-7b77-470c-a716-cfa52fd46cc5
# empty statement
emptyStatement = ";";

# ╔═╡ a451d245-7d95-44b5-8479-25df8b16cbb5
# constant
constant = Either(
	fullIdent,
	Optional(CharIn("+-")) * intLit,
	Optional(CharIn("+-")) * floatLit,
	strLit,
	boolLit
);

# ╔═╡ 833a0139-ae44-4f53-a2bf-a144e16d919c
# syntax to define proto version
# example:   syntax="proto3";
syntax = !("syntax" * _equals * _quote * "proto3" * _quote * ";");

# ╔═╡ fe36b63c-0a29-4b2a-879b-3a73381bd672
syntax("syntax=\"proto3\";")

# ╔═╡ e021f2ca-cfcd-444f-a7d9-dee88a129c97
# import statement
# example: import public "other.proto";
_import = Sequence(
	"import", whitespace, 
	:mod=>Optional(Either("weak", "public") * whitespace),
	:path=>strLit, ";"
);

# ╔═╡ 2e3c73da-6543-4690-859a-b7952ea3ce59
_import("import public \"other.proto\";")

# ╔═╡ d75b7bd3-6b38-46c1-9b2f-5317767a4573
# package statement
# example: package foo.bar;
_package = Sequence(
	"package", whitespace,
	:ident=>fullIdent, ";"
);

# ╔═╡ 4135fc07-8248-4002-bf25-0f725489625f
_package("package foo.bar;")

# ╔═╡ ed64df3e-e2cd-49a3-be81-90eeb844541f
# option statement
# example:  option java_package = "com.example.foo";
begin
	optionName = Either(ident, "(" * fullIdent * ")") * Repeat(period * ident)
	_option = "option" * whitespace * optionName * _equals * constant * ";"
end;

# ╔═╡ 3dbdd248-d042-4f5c-9978-69654c475743
# fields
begin
	fieldType = !Either(
		"double", "float", "int32", "int64", "uint32", "uint64",
		"sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64",
		"bool", "string", "bytes", messageType, enumType
	)
	fieldNumber = intLit
	fieldOption = Sequence(:name=>optionName, _equals, :val=>constant)
	fieldOptions = fieldOption * Repeat("," * ws * fieldOption)
	fieldMaybeOptions = Sequence(
		ws, 
		Optional('[' * fieldOptions * ']'), 
		';'
	)
	field = Sequence(
		Optional("repeated" * whitespace),
		:type=>fieldType, whitespace,
		:name=>fieldName, _equals, :num=>fieldNumber, 
		fieldMaybeOptions
	)
end;

# ╔═╡ d1baf6d8-c537-4b43-af97-4e216544f961
#field("repeated string x = 4 ;")

# ╔═╡ ade4156c-e206-4667-bd3f-8cda0368efcb
# oneofs
begin
	oneofField = fieldType * whitespace * fieldName * _equals * fieldNumber * ws * Optional('[' * fieldOptions * ']') * ';'
	oneof = Sequence(
		"oneof", ws, oneofName, ws, '{',
		Repeat(_option | oneofField | emptyStatement),
		ws, '}'
	)
end;

# ╔═╡ 4f705d5c-af6e-43b4-97a6-ed6e00bbcd69
# maps
begin
	keyType = Either(
		"int32", "int64', uint32", "unit64", "sint32", "sint64",
		"fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string"
	)
	mapField = Sequence(
		"map", ws, "<", keyType, ",", ws, fieldType, ">", ws,
		mapName, _equals, fieldNumberAndOptions
	)
end;

# ╔═╡ bd06257e-dd57-410d-8a85-728425749285
# reserved statements
# example: reserved 2, 15, 9 to 11;
# example: reserved "foo", "bar";
begin
	fieldNames = fieldName * Repeat(',' * ws * fieldName)
	range = intLit * Optional(Sequence(" to ", intLit | "max"))
	ranges = range * Repeat(',' * ws * range)
	reserved = Sequence(
		"reserved", whitespace, ranges | fieldNames
	)
end;

# ╔═╡ b97ba68f-426e-4d8f-8af0-b4c66050b14a
# enums
# example:
#	enum XX {
#		option allow_alias = true;
#		UNKNOWN = 0;
#	}
begin
	enumValueOption = optionName * _equals * constant
	enumField = Sequence(
		:fieldname=>ident, _equals, 
		:fieldnum=>!Sequence(Optional('-'), intLit),
		Optional(Sequence('[', enumValueOption, 
				Repeat(Sequence(',', ws, enumValueOption)), ']')), ';'
	)
	enumBody = Sequence(2, 
		'{', Repeat(Either(_option, enumField, emptyStatement)), '}'
	)
	enum = Sequence(
		"enum", whitespace, :name=>enumName, ws, :body=>enumBody
	)
end;

# ╔═╡ 40dc7e13-d531-44a0-853d-6de9b4669275
enum("""enum XXX {
	UNKNOWN = 0;
	AAA = 1;
	BBB = 2;
}""")

# ╔═╡ 2ee90ff6-183c-44d0-8f7f-523600a19aab
# message definitions
begin
	innerMessageBody = Sequence(
		'{', ws,
		Repeat(Either(field, enum, _option, oneof, mapField, reserved, emptyStatement) * ws),
		'}'
	)
	innerMessage = Sequence(
		"message", whitespace, messageName, ws, innerMessageBody
	)
	messageBody = Sequence(
		'{', ws,
		Repeat(Either(field, enum, innerMessage, _option, oneof, mapField, reserved, emptyStatement) * ws),
		'}'
	)
	message = Sequence(
		"message", whitespace, messageName, ws, messageBody
	)
end;

# ╔═╡ d1687636-ebb8-411f-8bc6-2e37095713af
# service definitions
begin
	rpc = Sequence(
		"rpc", whitespace, rpcName, ws, 
		'(', Optional("stream "), messageType, ')',
		whitespace, "returns", whitespace,
		'(', Optional("stream "), messageType, ')',
		Either(
			Sequence('{', _option | emptyStatement, '}'),
			';'
		)
	)
	service = Sequence(
		"service", whitespace, serviceName, ws, '{', ws,
		Repeat(Either(_option, rpc, emptyStatement) * ws),
		'}'
	)
end;

# ╔═╡ 094384db-1eb8-48dc-a892-48304e3b3501
# a complete proto file
begin
	topLevelDef = Either(message, enum, service)
	proto = Sequence(
		ws, syntax,
		Repeat(ws * Either(_import, _package, _option, topLevelDef, emptyStatement))
	)
end;

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CombinedParsers = "5ae71ed2-6f8a-4ed1-b94f-e14e8158f19e"

[compat]
CombinedParsers = "~0.1.7"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[AbstractTrees]]
git-tree-sha1 = "03e0550477d86222521d254b741d470ba17ea0b5"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.3.4"

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[AutoHashEquals]]
git-tree-sha1 = "45bb6705d93be619b81451bb2006b7ee5d4e4453"
uuid = "15f4f7f2-30c1-5605-9d31-71845cf9641f"
version = "0.2.0"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "ad613c934ec3a3aa0ff19b91f15a16d56ed404b5"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.0.2"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[CombinedParsers]]
deps = ["AbstractTrees", "AutoHashEquals", "Dates", "InternedStrings", "Nullables", "ReversedStrings", "TextParse", "Tries"]
git-tree-sha1 = "4f9a2f9c22f2053a8aeb9ad75cf787bb299df766"
uuid = "5ae71ed2-6f8a-4ed1-b94f-e14e8158f19e"
version = "0.1.7"

[[Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "344f143fa0ec67e47917848795ab19c6a455f32c"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.32.0"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[DataAPI]]
git-tree-sha1 = "ee400abb2298bd13bfc3df1c412ed228061a2385"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.7.0"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "4437b64df1e0adccc3e5d1adbc3ac741095e4677"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.9"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "a32185f5428d3986f47c2ab78b1f216d5e6cc96f"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.5"

[[DoubleFloats]]
deps = ["GenericLinearAlgebra", "LinearAlgebra", "Polynomials", "Printf", "Quadmath", "Random", "Requires", "SpecialFunctions"]
git-tree-sha1 = "1c962cf7e75c09a5f1fbf504df7d6a06447a1129"
uuid = "497a8b3b-efae-58df-a0af-a86822472b78"
version = "1.1.23"

[[Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[ExprTools]]
git-tree-sha1 = "b7e3d17636b348f005f11040025ae8c6f645fe92"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.6"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[GenericLinearAlgebra]]
deps = ["LinearAlgebra", "Printf", "Random"]
git-tree-sha1 = "ff291c1827030ffaacaf53e3c83ed92d4d5e6fb6"
uuid = "14197337-ba66-59df-a3e3-ca00e7dcff7a"
version = "0.2.5"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[InternedStrings]]
deps = ["Random", "Test"]
git-tree-sha1 = "eb05b5625bc5d821b8075a77e4c421933e20c76b"
uuid = "7d512f48-7fb1-5a58-b986-67e6dc259f01"
version = "0.7.0"

[[Intervals]]
deps = ["Dates", "Printf", "RecipesBase", "Serialization", "TimeZones"]
git-tree-sha1 = "323a38ed1952d30586d0fe03412cde9399d3618b"
uuid = "d8418881-c3e1-53bb-8760-2df7ec849ed5"
version = "1.5.0"

[[JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "642a199af8b68253517b80bd3bfd17eb4e84df6e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.3.0"

[[LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[LinearAlgebra]]
deps = ["Libdl"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LogExpFunctions]]
deps = ["DocStringExtensions", "LinearAlgebra"]
git-tree-sha1 = "7bd5f6565d80b6bf753738d2bc40a5dfea072070"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.2.5"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[Mocking]]
deps = ["ExprTools"]
git-tree-sha1 = "748f6e1e4de814b101911e64cc12d83a6af66782"
uuid = "78c3b35d-d492-501b-9361-3d52fe80e533"
version = "0.7.2"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "3927848ccebcc165952dc0d9ac9aa274a87bfe01"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "0.2.20"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[Nullables]]
git-tree-sha1 = "8f87854cc8f3685a60689d8edecaa29d2251979b"
uuid = "4d1e1d77-625e-5b40-9113-a560ec7a8ecd"
version = "1.0.0"

[[OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[Polynomials]]
deps = ["Intervals", "LinearAlgebra", "MutableArithmetics", "RecipesBase"]
git-tree-sha1 = "0bbfdcd8cda81b8144de4be8a67f5717e959a005"
uuid = "f27b6e38-b328-58d1-80ce-0feddd5e7a45"
version = "2.0.14"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "00cfd92944ca9c760982747e9a1d0d5d86ab1e5a"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.2"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[Quadmath]]
deps = ["Printf", "Random", "Requires"]
git-tree-sha1 = "5a8f74af8eae654086a1d058b4ec94ff192e3de0"
uuid = "be4d8f0f-7fa4-5f49-b795-2f01399ab2dd"
version = "0.5.5"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[RecipesBase]]
git-tree-sha1 = "b3fb709f3c97bfc6e948be68beeecb55a0b340ae"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.1.1"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "4036a3bd08ac7e968e27c203d45f5fff15020621"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.1.3"

[[ReversedStrings]]
deps = ["AutoHashEquals"]
git-tree-sha1 = "627a03e277371491d8db73b63ad20294199158b4"
uuid = "d6a58270-6f46-44a2-ab4b-2a767377cb4b"
version = "0.1.0"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[SpecialFunctions]]
deps = ["ChainRulesCore", "LogExpFunctions", "OpenSpecFun_jll"]
git-tree-sha1 = "508822dca004bf62e210609148511ad03ce8f1d8"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "1.6.0"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[TextParse]]
deps = ["CodecZlib", "DataStructures", "Dates", "DoubleFloats", "Mmap", "Nullables", "WeakRefStrings"]
git-tree-sha1 = "af728c38c839aee693637e15e244074a02f16c68"
uuid = "e0df1984-e451-5cb5-8b61-797a481e67e3"
version = "1.0.1"

[[TimeZones]]
deps = ["Dates", "Future", "LazyArtifacts", "Mocking", "Pkg", "Printf", "RecipesBase", "Serialization", "Unicode"]
git-tree-sha1 = "81753f400872e5074768c9a77d4c44e70d409ef0"
uuid = "f269a46b-ccf7-5d73-abea-4c690281aa53"
version = "1.5.6"

[[TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "7c53c35547de1c5b9d46a4797cf6d8253807108c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.5"

[[Tries]]
deps = ["AbstractTrees"]
git-tree-sha1 = "9bb6a6efd74e0f315a6e5bd73c15b58ac5a6de2c"
uuid = "666c268a-d78f-417b-b45a-09e10b365109"
version = "0.1.4"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[WeakRefStrings]]
deps = ["DataAPI", "Random", "Test"]
git-tree-sha1 = "28807f85197eaad3cbd2330386fac1dcb9e7e11d"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "0.6.2"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╠═381e09a0-f243-11eb-2bf8-99677165e439
# ╠═c5ff4ddd-0c52-45e3-bd24-808b4a61ac9f
# ╟─ba772876-a0a5-46b1-83e0-e92236567df5
# ╠═1d155e37-26d3-47c5-961c-8575b37cf525
# ╠═a9e631f8-f21e-4802-823e-f4742c8eb1d8
# ╠═c43e4f2e-4f4a-4d07-8864-36d1abee1cac
# ╠═0aeacc7d-8ccc-48ab-950c-dc49d9e05daa
# ╠═1958eaef-fb25-4b85-aa91-3c251d17ae89
# ╠═1f0d70fd-e924-4053-9bf6-42e4c69a64f6
# ╠═e650f905-f867-4011-a995-265f08bfddd0
# ╠═8f83eb51-6ffe-4059-a871-9bc72f6eefe4
# ╠═c6f30865-c82f-43c1-a406-c789542cced1
# ╠═e2b67ef1-8c9b-4c1f-a217-1b860a7c7fbf
# ╠═7b05dbdd-dfc2-4ad1-9811-285f7f7a20c7
# ╠═db8069fb-c088-4421-97ba-6beedeb16f81
# ╠═67fdaab4-beed-4d93-b7a3-d0f93aa6dece
# ╠═eac881c7-7b77-470c-a716-cfa52fd46cc5
# ╠═a451d245-7d95-44b5-8479-25df8b16cbb5
# ╠═833a0139-ae44-4f53-a2bf-a144e16d919c
# ╠═fe36b63c-0a29-4b2a-879b-3a73381bd672
# ╠═e021f2ca-cfcd-444f-a7d9-dee88a129c97
# ╠═2e3c73da-6543-4690-859a-b7952ea3ce59
# ╠═d75b7bd3-6b38-46c1-9b2f-5317767a4573
# ╠═4135fc07-8248-4002-bf25-0f725489625f
# ╠═ed64df3e-e2cd-49a3-be81-90eeb844541f
# ╠═3dbdd248-d042-4f5c-9978-69654c475743
# ╠═d1baf6d8-c537-4b43-af97-4e216544f961
# ╠═ade4156c-e206-4667-bd3f-8cda0368efcb
# ╠═4f705d5c-af6e-43b4-97a6-ed6e00bbcd69
# ╠═bd06257e-dd57-410d-8a85-728425749285
# ╠═b97ba68f-426e-4d8f-8af0-b4c66050b14a
# ╠═40dc7e13-d531-44a0-853d-6de9b4669275
# ╠═2ee90ff6-183c-44d0-8f7f-523600a19aab
# ╠═d1687636-ebb8-411f-8bc6-2e37095713af
# ╠═094384db-1eb8-48dc-a892-48304e3b3501
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
