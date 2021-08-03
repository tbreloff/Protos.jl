
module Specs

# types

type_pairs = [
    ("double", Float64),
    ("float", Float32),
    ("int32", Int32),
    ("int64", Int64),
    ("uint32", UInt32),
    ("uint64", UInt64),
    ("sint32", Int32),
    ("sint64", Int64),
    ("fixed32", Int32),
    ("fixed64", Int64),
    ("sfixed32", Int32),
    ("sfixed64", Int64),
    ("bool", Bool),
    ("string", String),
    ("bytes", Vector{UInt8})
]
str_to_type = Dict{String, Type}(p[1]=>p[2] for p in Specs.type_pairs)
type_to_str = Dict{Type, String}(p[2]=>p[1] for p in Specs.type_pairs)

function to_type(s)
    if haskey(str_to_type, s)
        str_to_type[s]
    else
        # ex: "Int64" --> Int64
        eval(Symbol(s))
    end
end

# options

struct Option
    key::String
    value::String
    comments::Union{Missing, String}
end

function Option(o::NamedTuple)
    Option(o.key, o.value, o.comments)
end

# fields

abstract type MessageField end

struct NormalField <: MessageField
    name::AbstractString
    comments::Union{Missing, String}
    t::AbstractString
    num::Int64
end

function NormalField(o::NamedTuple)
    @show o
    f = o.field
    NormalField(f.name, o.comments, f.type, f.num)
end

struct MapField <: MessageField
    name::AbstractString
    comments::Union{Missing, String}
    key_type::AbstractString
    value_type::AbstractString
    num::Int64
end

function MapField(o::NamedTuple)
    f = o.field
    MapField(f.name, o.comments, 
        f.keyType, 
        f.valueType, 
        f.num)
end


# reserved fields

abstract type Reserved end

struct ReservedRange <: Reserved
    low::Int64
    high::Int64
    comments::Union{Missing, String}
end

struct ReservedName <: Reserved
    name::AbstractString
    comments::Union{Missing, String}
end

# enums

struct EnumValue
    name::AbstractString
    comments::Union{Missing, String}
    num::Int64
end

function EnumValue(o::NamedTuple)
    EnumValue(o.field.fieldname, o.comments, o.field.fieldnum)
end

struct EnumSpec
    name::AbstractString
    comments::Union{Missing, String}
    values::Vector{EnumValue}
    EnumSpec(name, comments) = new(name, comments, EnumValue[])
end

Base.push!(es::EnumSpec, ev::EnumValue) = push!(es.values, ev)

function EnumSpec(o::NamedTuple)
    es = EnumSpec(o.enumName, o.comments)
    for v in o.fields
        push!(es, spec(v))
    end
    es
end

# messages

struct Message
    name::AbstractString
    comments::Union{Missing, String}
    fields::Vector{MessageField}
    reserved::Vector{Reserved}
    inner_messages::Vector{Message}
    inner_enums::Vector{EnumSpec}
    Message(name::AbstractString, comments) = new(name, comments, MessageField[], Reserved[], Message[], EnumSpec[])
end

Base.push!(m::Message, o::MessageField) = push!(m.fields, o)
Base.push!(m::Message, o::Reserved) = push!(m.reserved, o)
Base.push!(m::Message, o::Message) = push!(m.inner_messages, o)
Base.push!(m::Message, o::EnumSpec) = push!(m.inner_enums, o)

function Message(o::NamedTuple)
    m = Message(o.messageName, o.comments)
    for f in o.fields
        push!(m, spec(f))
    end
    m
end

# oneofs

struct OneOf <: MessageField
    name::AbstractString
    comments::Union{Missing, String}
    fields::Vector{MessageField}
    OneOf(name, comments) = new(name, comments, MessageField[])
end

Base.push!(oneof::OneOf, f::MessageField) = push!(oneof.fields, f)

function OneOf(o::NamedTuple)
    oneof = OneOf(o.field.oneofName, o.comments)
    for f in o.field.fields
        push!(oneof, spec(f))
    end
    oneof
end

# rpcs

struct Rpc
    name::AbstractString
    comments::Union{Missing, String}
    input_type::AbstractString
    output_type::AbstractString
    input_is_stream::Bool
    output_is_stream::Bool
end

Rpc(o::NamedTuple) = Rpc(o.rpcName, o.comments, 
    o.inputType,
    o.outputType,
    o.inputIsStream, o.outputIsStream)

# services

struct Service
    name::AbstractString
    comments::Union{Missing, String}
    rpcs::Vector{Rpc}
    Service(name, comments) = new(name, comments, Rpc[])
end

Base.push!(serice::Service, rpc::Rpc) = push!(service.rpcs, rpc)

function Service(o::NamedTuple)
    s = Service(o.serviceName, o.comments) 
    for f in o.rpcs
        push!(s, spec(f))
    end
    s
end

# proto files

mutable struct ProtoFile
    comments::Union{Missing, String}
    package::Union{Missing, String}
    imports::Vector{String}
    options::Vector{Option}
    messages::Vector{Message}
    enums::Vector{EnumSpec}
    services::Vector{Service}
    ProtoFile(comments) = new(comments, 
        missing, String[], Option[],
        Message[], EnumSpec[], Service[])
end

Base.push!(pf::ProtoFile, o::String) = push!(pf.imports, o)
Base.push!(pf::ProtoFile, o::Option) = push!(pf.options, o)
Base.push!(pf::ProtoFile, o::Message) = push!(pf.messages, o)
Base.push!(pf::ProtoFile, o::EnumSpec) = push!(pf.enums, o)
Base.push!(pf::ProtoFile, o::Service) = push!(pf.services, o)

function ProtoFile(o::NamedTuple)
    pf = ProtoFile(o.comment)
    for stmt in o.statements
        if haskey(stmt, :package)
            pf.package = stmt.package
        else
            push!(pf, spec(stmt))
        end
    end
    pf
end

# general conversion

function spec(o::NamedTuple)
    if haskey(o, :messageName)
        Message(o)
    elseif haskey(o, :enumName)
        EnumSpec(o)
    elseif haskey(o, :field)
        if haskey(o.field, :keyType)
            MapField(o)
        elseif haskey(o.field, :name)
            NormalField(o)
        elseif haskey(o.field, :oneofName)
            OneOf(o)
        elseif haskey(o.field, :fieldname)
            EnumValue(o)
        else
            throw("Unknown spec with field: $o")
        end
    elseif haskey(o, :rpcName)
        Rpc(o)
    elseif haskey(o, :serviceName)
        Service(o)
    elseif haskey(o, :key)
        Option(o)
    else
        throw("Unhandled spec: $o")
    end
end

end # module