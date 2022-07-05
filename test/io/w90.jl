using YAML

mat2vec(A::AbstractMatrix) = [Vector(A[:, i]) for i = 1:size(A, 2)]


@testset "read win" begin
    test_data = YAML.load_file(String(@__DIR__) * "/test_data/win.yaml")

    win = read_win("$FIXTURE_PATH/silicon.win")

    # Convert type so YAML can write it.
    unit_cell = mat2vec(win.unit_cell)
    kpoints = mat2vec(win.kpoints)

    # YAML.write_file(String(@__DIR__) * "/test_data/win.yaml", win)

    @test begin
        test_kpath = test_data["kpoint_path"]
        win_kpath = win.kpoint_path
        # println(test_kpath)
        # println(win_kpath)

        length(test_kpath) != length(win_kpath) && return false

        for i = 1:length(win_kpath)
            # a Pair: "L" => [0.5, 0.5, 0.5]
            (w1_lab, w1_vec), (w2_lab, w2_vec) = win_kpath[i]
            # YAML output is a Dict: Dict("L" => [0.5, 0.5, 0.5])
            tk1, tk2 = test_kpath[i]
            t1_lab, t1_vec = [(k, v) for (k, v) in tk1][1]
            t2_lab, t2_vec = [(k, v) for (k, v) in tk2][1]

            w1_lab != t1_lab && return false
            w1_vec ≉ t1_vec && return false
            w2_lab != t2_lab && return false
            w2_vec ≉ t2_vec && return false
        end
        true
    end

    @test test_data["num_wann"] == win.num_wann
    @test test_data["num_bands"] == win.num_bands
    @test test_data["unit_cell"] ≈ unit_cell
    @test test_data["mp_grid"] == win.mp_grid
    @test test_data["kpoints"] ≈ kpoints
end


@testset "read/write mmn" begin
    M, kpb_k, kpb_b = read_mmn("$FIXTURE_PATH/silicon.mmn")

    tmpfile = tempname(cleanup = true)

    write_mmn(tmpfile, M, kpb_k, kpb_b)

    M2, kpb_k2, kpb_b2 = read_mmn(tmpfile)

    @test M ≈ M2
    @test kpb_k ≈ kpb_k2
    @test kpb_b ≈ kpb_b2
end


@testset "read/write eig" begin
    E = read_eig("$FIXTURE_PATH/silicon.eig")

    tmpfile = tempname(cleanup = true)

    write_eig(tmpfile, E)

    E2 = read_eig(tmpfile)

    @test E ≈ E2
end


@testset "read_seedname" begin
    model = read_seedname("$FIXTURE_PATH/silicon")

    @test model.n_bands ≈ 12
    @test model.n_wann ≈ 8
    @test model.n_kpts ≈ 64
end


@testset "read nnkp" begin
    test_data = YAML.load_file(String(@__DIR__) * "/test_data/nnkp.yaml")

    bvectors = read_nnkp("$FIXTURE_PATH/silicon.nnkp")

    # Convert type so YAML can write it.
    kpb_b = bvectors.kpb_b
    dict = Dict(
        "recip_lattice" => mat2vec(bvectors.recip_lattice),
        "kpoints" => mat2vec(bvectors.kpoints),
        "bvectors" => mat2vec(bvectors.bvectors),
        "kpb_k" => mat2vec(bvectors.kpb_k),
        "kpb_b" => [mat2vec(kpb_b[:, :, ik]) for ik = 1:size(kpb_b, 3)],
    )

    # YAML.write_file(String(@__DIR__) * "/test_data/nnkp.yaml", dict)

    for (key, value) in dict
        @test value ≈ test_data[key]
    end
end


@testset "read/write unk" begin
    ik, Ψ = read_unk("$FIXTURE_PATH/UNK00001.1")

    tmpfile = tempname(cleanup = true)

    write_unk(tmpfile, ik, Ψ)

    ik2, Ψ2 = read_unk(tmpfile)

    @test ik ≈ ik2
    @test Ψ ≈ Ψ2
end


@testset "read chk" begin
    chk = read_chk("$FIXTURE_PATH/silicon.chk.fmt")

    @test chk.n_wann == 8
    @test chk.n_bands == 12

end

@testset "read/write w90 band dat" begin
    band = read_w90_bands("$FIXTURE_PATH/valence/band/silicon")

    outdir = mktempdir(cleanup = true)
    outseedname = joinpath(outdir, "silicon")

    write_w90_bands(
        outseedname,
        band.kpoints,
        band.E,
        band.x,
        band.symm_idx,
        band.symm_label,
    )

    band2 = read_w90_bands(outseedname)

    @test band.kpoints ≈ band2.kpoints
    @test band.E ≈ band2.E
    @test band.x ≈ band2.x
    @test band.symm_idx == band2.symm_idx
    @test band.symm_label == band2.symm_label
end

@testset "read wout" begin
    wout = read_wout("$FIXTURE_PATH/valence/band/silicon.wout")

    ref_unit_cell =
        [
            -2.698804 0.000000 2.698804
            0.000000 2.698804 2.698804
            -2.698804 2.698804 0.000000
        ]'
    ref_atoms = [
        -0.25000 0.75000 -0.25000
        0.00000 0.00000 0.00000
    ]'
    ref_centers =
        [
            -0.659352 0.658238 -0.680969
            0.669283 0.695828 0.666806
            0.682490 -0.683846 -0.683726
            -0.701673 -0.656575 0.703751
        ]'
    ref_spreads = [
        2.39492617
        2.19372718
        1.83863803
        1.88512458
    ]

    @test wout.unit_cell ≈ ref_unit_cell
    @test wout.atoms ≈ ref_atoms
    @test wout.centers ≈ ref_centers
    @test wout.spreads ≈ ref_spreads
end
