using Protos
using Test

@testset "Protos.jl" begin
    @testset "parsing" begin
        testfile = joinpath(@__DIR__, "test.proto")
        io = open(testfile)
        parsed = parse_proto(io)
        @show parsed
        @test parsed.comment == "\nThis is a file-wide comment.\n"
        @test parsed.statements[1].package == "some.package.name"
        @test parsed.statements[2].value == "some.other.package.name"
        
        # TODO: ensure both messages and enum are present
    end
end
