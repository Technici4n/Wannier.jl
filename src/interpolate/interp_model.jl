struct InterpolationModel{T<:Real}
    # model storing results of Wannierization
    model::Model{T}

    # R vectors for Fourier transform
    kRvectors::KRVectors{T}

    # kpoint path for band structure
    kpath::KPath

    # spin matrix, n_bands * n_bands * 3 * n_kpts
    S::Array{Complex{T},4}
end

function Base.getproperty(x::InterpolationModel, sym::Symbol)
    if sym ∈ fieldnames(Model)
        return getfield(x.model, sym)
    elseif sym ∈ fieldnames(KRVectors)
        return getfield(x.kRvectors, sym)
    elseif sym == :n_rvecs
        return getproperty(x.kRvectors, sym)
    else
        # fallback to getfield
        getfield(x, sym)
    end
end

function Base.show(io::IO, model::InterpolationModel)
    @info "model"
    show(io, model.model)
    println(io, "\n")

    @info "k & R vectors"
    show(io, model.kRvectors)
    println(io, "\n")

    @info "kpath"
    show(io, "text/plain", model.kpath)
    return nothing
end

function InterpolationModel(
    model::Model{T}, kRvectors::KRVectors{T}, kpath::KPath
) where {T<:Real}
    n_bands = model.n_bands
    n_kpts = model.n_kpts
    return InterpolationModel(
        model, kRvectors, kpath, Array{Complex{T},4}(undef, n_bands, n_bands, 3, n_kpts)
    )
end

function InterpolationModel(model::Model; mdrs::Bool=true)
    if mdrs
        centers = center(model)
        # from cartesian to fractional
        centers = inv(model.lattice) * centers
        Rvecs = get_Rvectors_mdrs(model.lattice, model.kgrid, centers)
    else
        Rvecs = get_Rvectors_ws(model.lattice, model.kgrid)
    end
    kRvecs = KRVectors(model.lattice, model.kgrid, model.kpoints, Rvecs)

    kpath = get_kpath(model.lattice, model.atom_positions, model.atom_labels)

    return InterpolationModel(model, kRvecs, kpath)
end