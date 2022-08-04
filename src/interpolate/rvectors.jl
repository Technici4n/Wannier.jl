using LinearAlgebra
import NearestNeighbors as NN

@doc raw"""
The R vectors for interpolations, sorted in the same order as the W90 nnkp file.
"""
struct RVectors{T<:Real}
    # lattice, 3 * 3, Å unit
    # each column is a lattice vector
    lattice::Mat3{T}

    # grid size along x,y,z, actually equal to kgrid
    grid::Vec3{Int}

    # R vectors, 3 * n_rvecs
    # fractional (actually integers) coordinates w.r.t lattice
    R::Matrix{Int}

    # degeneracy of each Rvec, n_rvecs
    # weight = 1 / degeneracy
    N::Vector{Int}
end

function Base.getproperty(x::RVectors, sym::Symbol)
    if sym == :n_rvecs
        return size(x.R, 2)
    else
        # fallback to getfield
        getfield(x, sym)
    end
end

function RVectors(
    lattice::AbstractMatrix,
    grid::AbstractVector{T},
    R::AbstractMatrix{T},
    N::AbstractVector{T},
) where {T<:Integer}
    return RVectors(Mat3(lattice), Vec3(grid), R, N)
end

function check_weights(R::RVectors)
    if sum(1 ./ R.N) ≉ prod(R.grid)
        error("weights do not sum to 1")
    end
end

"""
atol: equivalent to `ws_distance_tol` in wannier90.
max_cell: equivalent to `ws_search_size` in wannier90.
"""
function get_Rvectors_ws(
    lattice::AbstractMatrix{T}, rgrid::AbstractVector{R}; atol::T=1e-5, max_cell::Int=3
) where {T<:Real,R<:Integer}
    # 1. Generate a supercell where WFs live in
    supercell_wf, _ = make_supercell(zeros(Int, 3, 1), [0:(r - 1) for r in rgrid])
    # another supercell of the supercell_wf to find the Wigner Seitz cell of the supercell_wf
    supercell, translations = make_supercell(
        supercell_wf, [((-max_cell):max_cell) * r for r in rgrid]
    )
    # sort so z increases fastest, to make sure the Rvec order is the same as W90
    supercell = sort_kpoints(supercell)
    # to cartesian coordinates
    supercell_cart = lattice * supercell
    # get translations of supercell_wf, only need unique points
    translations = unique(translations; dims=2)
    translations_cart = lattice * translations

    # 2. KDTree to get the distance of supercell points to translations of lattice_wf
    kdtree = NN.KDTree(translations_cart)
    # in priciple, need to calculate distances to all the supercell translations to
    # count degeneracies, this need a search of `size(translations_cart, 2)` neighbors.
    # usually we don't need such high degeneracies, so I only search for 8 neighbors.
    max_neighbors = min(8, size(translations_cart, 2))
    idxs, dists = NN.knn(kdtree, supercell_cart, max_neighbors, true)

    # 3. supercell_cart point which is closest to lattice_wf at origin is inside WS cell
    idx_origin = findvector(==, [0, 0, 0], translations)
    R_idxs = Vector{Int}()
    R_degen = Vector{Int}()
    for ir in axes(supercell_cart, 2)
        i = idxs[ir][1]
        d = dists[ir][1]
        if i != idx_origin
            # check again the distance, to reproduce W90's behavior
            d0 = norm(supercell_cart[:, ir])
            if abs(d - d0) >= atol
                continue
            end
        end
        push!(R_idxs, ir)
        degen = count(x -> abs(x - d) < atol, dists[ir])
        if degen == max_neighbors
            error("degeneracy is too large?")
        end
        push!(R_degen, degen)
    end
    # fractional coordinates
    R_vecs = supercell[:, R_idxs]

    Rvecs = RVectors(lattice, rgrid, R_vecs, R_degen)
    check_weights(Rvecs)

    return Rvecs
end

@doc raw"""
The R vectors for interpolations, sorted in the same order as the W90 nnkp file.
"""
struct RVectorsMDRS{U<:Real}
    # R vectors of the Wigner-Seitz interplation
    rvectors::RVectors{U}

    # translation vectors, fractional coordinates w.r.t lattice
    # internal matrix: 3 * n_degen, external array: n_wann * n_wann * n_rvecs
    T::Array{Matrix{Int},3}

    # degeneracy of each T vector, n_wann * n_wann * n_rvecs
    Nᵀ::Array{Int,3}
end

"""
centers: fractional coordinates, 3 * n_wann
"""
function get_Rvectors_mdrs(
    lattice::AbstractMatrix{T},
    rgrid::AbstractVector{Int},
    centers::AbstractMatrix{T};
    atol::T=1e-5,
    max_cell::Int=3,
) where {T<:Real}
    n_wann = size(centers, 2)
    Rvec = get_Rvectors_ws(lattice, rgrid; atol=atol, max_cell=max_cell)
    n_rvecs = Rvec.n_rvecs

    # 1. generate WS cell around origin to check WF |nR> is inside |m0> or not
    # increase max_cell by 1 in case WF center drifts away from the parallelepiped
    max_cell1 = max_cell + 1
    # supercell of the supercell_wf to find the Wigner Seitz cell of the supercell_wf,
    # supercell_wf is the cell where WFs live in
    supercell, translations = make_supercell(
        zeros(Int, 3, 1), [((-max_cell1):max_cell1) * r for r in rgrid]
    )
    # to cartesian coordinates
    supercell_cart = lattice * supercell
    # get translations of supercell_wf, only need unique points
    translations = unique(translations; dims=2)
    translations_cart = lattice * translations

    # 2. KDTree to get the distance of supercell points to translations of lattice_wf
    kdtree = NN.KDTree(translations_cart)
    # usually we don't need such high degeneracies, so I only search for 8 neighbors
    max_neighbors = min(8, size(translations_cart, 2))
    idx_origin = findvector(==, [0, 0, 0], translations)

    # save all translations and degeneracies
    T_vecs = Array{Matrix{Int}}(undef, n_wann, n_wann, n_rvecs)
    T_degen = zeros(Int, n_wann, n_wann, n_rvecs)

    for ir in 1:n_rvecs
        for m in 1:n_wann
            for n in 1:n_wann
                # translation vector of |nR> WFC relative to |m0> WFC
                Tᶠ = centers[:, n] + Rvec.R[:, ir] - centers[:, m]
                # to cartesian
                Tᶜ = supercell_cart .+ lattice * Tᶠ
                # get distances
                idxs, dists = NN.knn(kdtree, Tᶜ, max_neighbors, true)
                # collect T vectors
                T_idxs = Vector{Int}()
                for it in axes(Tᶜ, 2)
                    i = idxs[it][1]
                    d = dists[it][1]
                    if i != idx_origin
                        # check again the distance, to reproduce W90's behavior
                        if idx_origin ∉ idxs[it]
                            continue
                        end
                        j = findfirst(idxs[it] .== idx_origin)
                        d0 = dists[it][j]
                        if abs(d - d0) >= atol
                            continue
                        end
                    end
                    push!(T_idxs, it)
                end
                degen = length(T_idxs)
                if degen == max_neighbors
                    error("degeneracy of T vectors is too large?")
                end
                # fractional coordinates
                T_vecs[m, n, ir] = supercell[:, T_idxs]
                T_degen[m, n, ir] = degen
            end
        end
    end

    return RVectorsMDRS{T}(Rvec, T_vecs, T_degen)
end