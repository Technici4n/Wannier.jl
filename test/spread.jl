using NLSolversBase

# A reusable fixture for a model
model = read_w90(joinpath(FIXTURE_PATH, "silicon/silicon"))

fg! = Wannier.get_fg!_maxloc(model)

@testset "spread" begin
    # should be roughly the same as test/fixtures/silicon/silicon.wout
    Ω = omega(model)

    @test Ω.Ω ≈ 18.19526254033958
    @test Ω.ΩI ≈ 12.274068863079536
    @test Ω.ΩOD ≈ 5.843656489756686
    @test Ω.ΩD ≈ 0.07753718750335814
    @test Ω.Ω̃ ≈ 5.921193677260044

    ω_ref = [1.763839 2.443091 2.447297 2.443499 1.763839 2.443618 2.448038 2.442041]'
    @test isapprox(Ω.ω, ω_ref; atol=1e-5)

    r_ref = [
        1.349402 1.348405 1.349402 1.348402 0.000000 0.001000 -0.000000 0.000997
        1.349402 1.348821 1.348821 1.349402 -0.000000 0.000586 0.000576 0.000000
        1.349402 1.349402 1.348567 1.348564 0.000000 -0.000000 0.000834 0.000839
    ]
    r_ref = [Vec3(r_ref[:, i]) for i in 1:size(r_ref, 2)]
    @test isapprox(Ω.r, r_ref; atol=1e-5)
end

@testset "spread gradient" begin
    n_bands = size(model.U[1], 1)
    n_wann = size(model.U[1], 2)
    n_kpts = length(model.U)
    U = [model.U[ik][ib, ic] for ib in 1:n_bands, ic in 1:n_wann, ik in 1:n_kpts]
    G = zero(U)
    fg!(nothing, G, U)

    # Use finite difference as reference
    Uinit = deepcopy(U)
    d = NLSolversBase.OnceDifferentiable(
        x -> fg!(1.0, nothing, x), Uinit, real(zero(eltype(Uinit)))
    )
    G_ref = NLSolversBase.gradient!(d, U)

    @test isapprox(G, G_ref; atol=1e-7)
end

@testset "center" begin
    r = center(model)

    r_ref = [
        1.349402 1.348405 1.349402 1.348402 0.000000 0.001000 -0.000000 0.000997
        1.349402 1.348821 1.348821 1.349402 -0.000000 0.000586 0.000576 0.000000
        1.349402 1.349402 1.348567 1.348564 0.000000 -0.000000 0.000834 0.000839
    ]
    r_ref = [Vec3(r_ref[:, i]) for i in 1:size(r_ref, 2)]

    @test isapprox(r, r_ref; atol=1e-5)
end
