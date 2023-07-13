using Printf: @printf

export rotate_gauge

"""
    struct Model

A struct containing the parameters and matrices of the crystal structure.

# Fields
- `lattice`: columns are the lattice vectors
- `atom_positions`: columns are the fractional coordinates of atoms
- `atom_labels`: labels of atoms
- `kgrid`: number of kpoints along 3 lattice vectors
- `kpoints`: columns are the fractional coordinates of kpoints
- `bvectors`: bvectors satisfying the B1 condition
- `frozen_bands`: indicates which bands are frozen
- `M`: `n_bands * n_bands * n_bvecs * n_kpts`, overlap matrix ``M_{\\bm{k},\\bm{b}}``
- `U`: `n_bands * n_wann * n_kpts`, (semi-)unitary gauge rotation matrix ``U_{\\bm{k}}``
- `E`: `n_bands * n_kpts`, energy eigenvalues ``\\epsilon_{n \\bm{k}}``
- `recip_lattice`: columns are the reciprocal lattice vectors
- `n_atoms`: number of atoms
- `n_bands`: number of bands
- `n_wann`: number of wannier functions
- `n_kpts`: number of kpoints
- `n_bvecs`: number of bvectors

!!! note

    This only cotains the necessary information for maximal localization.
    For Wannier interpolation, see [`TBHamiltonian`](@ref).
"""
struct Model{T<:Real}
    # unit cell, 3 * 3, Å unit, each column is a lattice vector
    lattice::Mat3{T}

    # atomic positions, n_atoms of Vec3, fractional coordinates,
    atom_positions::Vector{Vec3{T}}

    # atomic labels, n_atoms
    atom_labels::Vector{String}

    # number of kpoints along 3 directions
    kgrid::Vec3{Int}

    # kpoints array, fractional coordinates, n_kpts of Vec3
    kpoints::Vector{Vec3{T}}

    # b vectors satisfying b1 condition
    bvectors::BVectors{T}

    # is band frozen? n_kpts of length-n_bands BitVector
    frozen_bands::Vector{BitVector}

    # Mmn matrix, n_kpts of n_bvecs of n_bands * n_bands matrix
    M::Vector{Vector{Matrix{Complex{T}}}}

    # the unitary transformation matrix, n_kpts of n_bands * n_wann matrix
    U::Vector{Matrix{Complex{T}}}

    # eigenvalues, n_kpts of length-n_bands vector
    E::Vector{Vector{T}}

    # I put these frequently used variables in the last,
    # since they are generated by the constructor.

    # reciprocal cell, 3 * 3, Å⁻¹ unit, each column is a lattice vector
    recip_lattice::Mat3{T}

    # number of atoms
    n_atoms::Int

    # number of bands
    n_bands::Int

    # number of Wannier functions (WFs)
    n_wann::Int

    # number of kpoints
    n_kpts::Int

    # number of b vectors
    n_bvecs::Int
end

"""
    Model(lattice, atom_positions, atom_labels, kgrid, kpoints, bvectors, frozen_bands, M, U, E)

Construct a [`Model`](@ref Model) `struct`.

# Arguments
- `lattice`: columns are the lattice vectors
- `atom_positions`: columns are the fractional coordinates of atoms
- `atom_labels`: labels of atoms
- `kgrid`: number of kpoints along 3 lattice vectors
- `kpoints`: columns are the fractional coordinates of kpoints
- `bvectors`: bvectors satisfying the B1 condition
- `frozen_bands`: indicates which bands are frozen
- `M`: `n_bands * n_bands * n_bvecs * n_kpts`, overlap matrix ``M_{\\bm{k},\\bm{b}}``
- `U`: `n_bands * n_wann * n_kpts`, (semi-)unitary gauge rotation matrix ``U_{\\bm{k}}``
- `E`: `n_bands * n_kpts`, energy eigenvalues ``\\epsilon_{n \\bm{k}}``

!!! tip

    This is more user-friendly constructor, only necessary information is required.
    Remaining fields are generated automatically.
"""
function Model(
    lattice::Mat3{T},
    atom_positions::Vector{Vec3{T}},
    atom_labels::AbstractVector{<:String},
    kgrid::Vec3{Int},
    kpoints::Vector{Vec3{T}},
    bvectors::BVectors{T},
    frozen_bands::Vector{BitVector},
    M,
    U,
    E,
) where {T<:Real}
    return Model(
        lattice,
        atom_positions,
        Vector(atom_labels),
        kgrid,
        kpoints,
        bvectors,
        frozen_bands,
        M,
        U,
        E,
        get_recip_lattice(lattice),
        length(atom_labels),
        size(U[1], 1),
        size(U[1], 2),
        length(U),
        bvectors.n_bvecs,
    )
end

n_wann(model) = isempty(model.U) ? 0 : size(model.U[1], 2)
n_bands(model) = isempty(model.U) ? 0 : size(model.U[1], 1)
n_kpts(model) = length(model.kpoints)
n_bvecs(model) = isempty(model.M) ? 0 : size(model.M[1], 3)

function Base.show(io::IO, model::Model)
    @printf(io, "lattice: Å\n")
    for i in 1:3
        @printf(io, "  a%d: %8.5f %8.5f %8.5f\n", i, model.lattice[:, i]...)
    end
    println(io)

    @printf(io, "atoms: fractional\n")
    for i in 1:(model.n_atoms)
        l = model.atom_labels[i]
        pos = model.atom_positions[i]
        @printf(io, " %3s: %8.5f %8.5f %8.5f\n", l, pos...)
    end
    println(io)

    @printf(io, "n_bands: %d\n", model.n_bands)
    @printf(io, "n_wann : %d\n", model.n_wann)
    @printf(io, "kgrid  : %d %d %d\n", model.kgrid...)
    @printf(io, "n_kpts : %d\n", model.n_kpts)
    @printf(io, "n_bvecs: %d\n", model.n_bvecs)

    println(io)
    show(io, model.bvectors)
    return nothing
end

"""
    rotate_gauge(model::Model, U::Array{T,3}; diag_H=false)

Rotate the gauge of a `Model`.

# Arguments
- `model`: a `Model` `struct`
- `U`: `n_bands * n_wann * n_kpts`, (semi-)unitary gauge rotation matrix ``U_{\\bm{k}}``

# Keyword Arguments
- `diag_H`: if after rotation, the Hamiltonian is not diagonal, then diagonalize it and
    save the eigenvalues to `model.E`, and the inverse of the eigenvectors to `model.U`,
    so that the `model` is still in the input gauge `U`.
    Otherwise, if the rotated Hamiltonian is not diagonal, raise error.

!!! note

    The original `Model.U` will be discarded;
    the `M`, and `E` matrices will be rotated by the input `U`.
    However, since `E` is not the Hamiltonian matrices but only the eigenvalues,
    if `diag_H = false`, this function only support rotations that keep the Hamiltonian
    in diagonal form.
"""
function rotate_gauge(
    model::Model, U::Vector{Matrix{T}}; diag_H::Bool=false
) where {T<:Number}
    n_bands = model.n_bands
    n_kpts = model.n_kpts
    (size(U[1], 1), length(U)) == (n_bands, n_kpts) ||
        error("U must have size (n_bands, :, n_kpts)")
    # The new n_wann
    n_wann = size(U[1], 2)

    # the new gauge is just identity
    U2 = eyes_U(eltype(U[1]), n_wann, n_kpts)

    # EIG
    E = model.E
    E2 = map(m -> similar(m), E)
    H = zeros(eltype(model.U[1]), n_wann, n_wann)
    # tolerance for checking Hamiltonian
    atol = 1e-8
    # all the diagonalized kpoints, used if diag_H = true
    diag_kpts = Int[]
    for ik in 1:n_kpts
        Uₖ = U[ik]
        H .= Uₖ' * diagm(0 => E[ik]) * Uₖ
        ϵ = diag(H)
        if norm(H - diagm(0 => ϵ)) > atol
            if diag_H
                # diagonalize the Hamiltonian
                ϵ, v = eigen(H)
                U2[ik] = v
                push!(diag_kpts, ik)
            else
                error("H is not diagonal after gauge rotation")
            end
        end
        if any(imag(ϵ) .> atol)
            error("H has non-zero imaginary part")
        end
        E2[ik] = real(ϵ)
    end

    # MMN
    M = model.M
    kpb_k = model.bvectors.kpb_k
    M2 = rotate_M(M, kpb_k, U)
    if diag_H && length(diag_kpts) > 0
        M2 = rotate_M(M2, kpb_k, U2)
        # the gauge matrix needs to save the inverse of the eigenvectors
        for ik in diag_kpts
            U2[ik] = inv(U2[ik])
        end
    end

    model2 = Model(
        model.lattice,
        model.atom_positions,
        model.atom_labels,
        model.kgrid,
        model.kpoints,
        model.bvectors,
        [falses(n_wann) for i in 1:n_kpts],
        M2,
        U2,
        E2,
    )
    return model2
end
