
# function generate_julia_code(protofile::NamedTuple)
#     io = IOBuffer()
#     for statement in protofile.statements
#         if haskey(statement, :messageName)
#             print_message(io, statement)
#         elseif haskey(statement, :enumName)
#             print_enum(io, statement)
#         elseif haskey(statement, :serviceName)
#             print_service(io, statement)
#         end
#         # TODO handle other stuff like package name, key/value pairs, etc
#     end
#     String(take!(io))
# end

_indent(indent) = " " ^ (4 * indent)

"""
generate a bunch of string representations for each element in arr.
the func should return a string representation of each element.
"""
gen_list(func::Function, arr) = join([func(x) for x in arr], "\n\n")

"""
indent the whole block
"""
indent(s::AbstractString, indent_num) = replace(s, "\n" => "\n$(_indent(indent_num))")


"""
return only the message fields
"""
function get_message_fields(arr)
    []
    filter(f -> haskey(f, :field) && haskey(f.field, :type), arr)
end

function get_message_oneofs(arr)
    oneofs = OneOf[]
    for f in arr
        if f -> haskey(f, :field) && haskey(f.field, :oneofName)
            push!(oneofs, OneOf(f.oneofName, get_message_fields(f.fields)))
        end
    end
end

"""
return only the enum fields
"""
function get_enum_fields(arr)
    filter(f -> haskey(f, :field) && haskey(f.field, :fieldname), arr)
end

"""
return only the messages
"""
function get_messages(arr)
    filter(f -> haskey(f, :messageName), arr)
end

function get_enums(arr)
    filter(f -> haskey(f, :enumName), arr)
end

builtins = Dict(
    "bool" => Bool,
    "string" => String,
    "uint32" => UInt32,
)

function julia_type(t)
    if haskey(builtins, t)
        builtins[t]
    else
        # ex: "Int64" --> Int64
        eval(Symbol(t))
    end
end


function comments_template(comment)
    ismissing(comment) ? "" : "#" * replace(comment, "\n" => "\n#") * "\n"
end

function message_field_template(o)
    f = o.field
    """$(comments_template(o.comments))
    $(f.name)::$(julia_type(f.type))
    """
end


function message_template(o; prefix="")
    fields = gen_list(
        message_field_template, 
        get_message_fields(o.fields))
    fields = gen_list(
        message_field_template, 
        get_oneof_fields(o.fields))
    inner_messages = gen_list(
        x -> message_template(x, prefix=o.messageName*"_"), 
        get_messages(o.fields))
    inner_enums = gen_list(
        x -> enum_template(x, prefix=o.messageName*"_"), 
        get_enums(o.fields))

    """$(comments_template(o.comments))struct $(prefix)$(o.messageName)
        $(indent(fields, 1))
        $(indent(oneofs, 1))
    end

    $inner_messages
    
    $inner_enums"""
end

function enum_field_template(o)
    f = o.field
    """$(comments_template(o.comments))$(f.fieldname) = $(f.fieldnum)"""
end

function enum_template(o; prefix="")
    fields = gen_list(
        enum_field_template, 
        get_enum_fields(o.fields))

    """$(comments_template(o.comments))@enum $(prefix)$(o.enumName) begin
        $(indent(fields, 1))
    end"""
end

# function print_message(io, statement; name_prefix="", indent=0)
#     ismissing(statement.comments) || print_comments(io, statement.comments)
#     ind = _indent(indent)
#     println(io, ind, "struct $(name_prefix)$(statement.messageName)")
#     inner_messages = NamedTuple[]
#     for field in statement.fields
#         print_message_statement(io, field, inner_messages; indent=indent+1)
#     end
#     println(io, ind, "end\n")

#     for msg in inner_messages
#         print_message(io, msg; name_prefix="$(statement.messageName)_", indent=indent)
#     end
# end

# function print_message_statement(io, stmt, inner_messages; indent=0)
#     if haskey(stmt, :messagName)
#         push!(inner_messages, stmt)
#     elseif haskey(stmt, :field)
#         print_message_field(io, stmt; indent=indent)
#     elseif haskey(stmt, :oneofName)
#         print_message_oneof(io, stmt)
#     end
#     # ismissing(stmt.comments) || print_comments(io, stmt.comments; indent=indent)
# end
