
"""
Generate valence only MMN, EIG files from a val+cond NSCF calculation.

Args:
    seedname: _description_
    outdir: the folder for writing MMN, EIG files.
"""
function truncate_mmn_eig(
    seedname::String, keep_bands::AbstractVector{Int}, outdir::String="truncate"
)
    !isdir(outdir) && mkdir(outdir)

    # for safety, in case seedname = "../si" then joinpath(outdir, seedname)
    # will overwrite the original file
    seedname_base = basename(seedname)

    E = read_eig("$seedname.eig")
    E1 = E[keep_bands, :]
    write_eig(joinpath(outdir, "$seedname_base.eig"), E1)

    M, kpb_k, kpb_b = read_mmn("$seedname.mmn")
    M1 = M[keep_bands, keep_bands, :, :]
    write_mmn(joinpath(outdir, "$seedname_base.mmn"), M1, kpb_k, kpb_b)

    return nothing
end

"""
Truncate UNK files for specified bands.

Args:
dir: folder of UNK files.
keep_bands: the band indexes to keep. Start from 1.
outdir: Defaults to 'truncated'.
"""
function truncate_unk(
    dir::String, keep_bands::AbstractVector{Int}, outdir::String="truncate"
)
    !isdir(outdir) && mkdir(outdir)

    regex = r"UNK(\d{5})\.\d"

    for unk in readdir(dir)
        m = match(regex, unk)
        m === nothing && continue

        println(unk)
        # for safety, in case unk = "../UNK00001.1" then joinpath(dir, unk)
        # will overwrite the original file
        unk_base = basename(unk)

        ik = parse(Int, m.captures[1])
        ik1, Ψ = read_unk(joinpath(dir, unk))
        @assert ik == ik1

        Ψ1 = Ψ[:, :, :, keep_bands]
        write_unk(joinpath(outdir, unk), ik, Ψ1)
    end

    return nothing
end

"""
Truncate AMN/MMN/EIG/UNK(optional) files.

Args:
    seedname: seedname for input AMN/MMN/EIG files.
    keep_bands: Band indexes to be kept, start from 1.
    unk: Whether truncate UNK files. Defaults to false.
    outdir: output folder
"""
function truncate_w90(
    seedname::AbstractString,
    keep_bands::AbstractVector{Int},
    outdir::AbstractString="truncate",
    unk::Bool=false,
)
    @info "Truncat AMN/MMN/EIG files"

    !isdir(outdir) && mkdir(outdir)

    # E = read_eig("$seedname.eig")
    # n_bands = size(E, 1)
    # keep_bands = [i for i = 1:n_bands if i ∉ exclude_bands]

    truncate_mmn_eig(seedname, keep_bands, outdir)

    dir = dirname(seedname)

    if unk
        truncate_unk(dir, keep_bands, outdir)
    end

    println("Truncated files written in ", outdir)
    return nothing
end
