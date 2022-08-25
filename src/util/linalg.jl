using LinearAlgebra

imaglog(z::T) where {T<:Complex} = atan(imag(z), real(z))

get_recip_lattice(lattice::Mat3) = 2π * inv(lattice)'
get_lattice(recip_lattice::Mat3) = inv(recip_lattice / (2π))'

"""
Normalize a matrix A to be (semi-)unitary.
If X is a matrix with orthogonal columns and A a non-singular matrix,
then Lowdin-orthogonalizing X*A is equivalent to computing X*normalize_matrix(A)
"""
function orthonorm_lowdin(A::Matrix{T}) where {T<:Union{Complex,Real}}
    U, S, V = svd(A)
    # @assert A ≈ U * Diagonal(S) * V'
    return U * V'
end

function orthonorm_lowdin(A::Array{T,3}) where {T<:Union{Complex,Real}}
    n_kpts = size(A, 3)

    B = similar(A)

    for ik in 1:n_kpts
        B[:, :, ik] .= orthonorm_lowdin(A[:, :, ik])
    end

    return B
end

function orthonorm_cholesky(A)
    return A / chol(A'A)
end

"""
Return a factor to fix the global phase of wavefunction,
such that the point having max norm is real.

W: usually size(W) = n_gx * n_gy * n_gz
"""
function fix_global_phase(W::AbstractArray)
    f = 1.0 + 0.0im
    # I use abs2 and findmax (returns the 1st maximum)
    # to exactly reproduce W90 behavior
    m, idx = findmax(abs2, W)
    if m > 0
        f = conj(W[idx]) / sqrt(m)
    end
    return f
end

"""Im/Re ratio"""
function compute_imre_ratio(W::AbstractArray)
    # only calculate real >= 0.01 elements, same as W90
    V = W[abs.(real(W)) .>= 0.01]
    if isempty(V)
        return 0.0
    end
    r = maximum(abs.(imag(V) ./ real(V)))
    return r
end

"""
Power of a unitary (or at least, normal) matrix A
"""
# TODO cleanup this, seems not used anymore
function powm(A::AbstractMatrix{T}, p::F) where {T<:Union{Complex,Real},F<:Real}
    # Workaround, eigen incompatible with lazy adjoint.
    d, V = eigen(Matrix(A))

    V = orthonorm_lowdin(V)
    # accuracy = norm(V * Diagonal(d) * V' - A)
    # @assert accuracy < 1e-10

    return V * Diagonal(d .^ p) * V'
end

"""Rotate the gauge of an operator"""
function rotate_gauge(O::Array{T,3}, A::Array{T,3}) where {T<:Number}
    n_bands, n_wann, n_kpts = size(A)
    size(O) != (n_bands, n_bands, n_kpts) &&
        error("O must have size (n_bands, n_bands, n_kpts)")

    O1 = similar(O, n_wann, n_wann, n_kpts)

    for ik in 1:n_kpts
        O1[:, :, ik] .= A[:, :, ik]' * O[:, :, ik] * A[:, :, ik]
    end

    return O1
end

function eyes_A(T::Type, n_wann::Int, n_kpts::Int)
    A = zeros(T, n_wann, n_wann, n_kpts)
    Iₖ = diagm(0 => ones(n_wann))

    for ik in 1:n_kpts
        A[:, :, ik] = Iₖ
    end

    return A
end

function eyes_A(T::Type, n_bands::Int, n_wann::Int, n_kpts::Int)
    A = zeros(T, n_bands, n_wann, n_kpts)
    n = min(n_bands, n_wann)
    Iₖ = diagm(0 => ones(n))

    for ik in 1:n_kpts
        A[1:n, 1:n, ik] = Iₖ
    end

    return A
end

function rotate_A(A::Array{T,3}, U::Array{T,3}) where {T<:Complex}
    n_bands, n_wann, n_kpts = size(A)
    size(U)[[1, 3]] != (n_wann, n_kpts) && error("U must be a n_wann x ? x n_kpts matrix")
    m = size(U, 2)

    A1 = similar(A, n_bands, m, n_kpts)

    for ik in 1:n_kpts
        A1[:, :, ik] .= A[:, :, ik] * U[:, :, ik]
    end

    return A1
end

"""
Rotate MMN matrices according to gauge U.
"""
@views function rotate_M(
    M::Array{T,4}, kpb_k::Matrix{Int}, U::Array{T,3}
) where {T<:Complex}
    n_bands, n_wann = size(U)
    n_kpts = size(M, 4)
    n_bvecs = size(M, 3)

    n_bands != size(M, 1) && error("incompatible n_bands")

    # Fill MMN
    N = similar(M, n_wann, n_wann, n_bvecs, n_kpts)

    for ik in 1:n_kpts
        for ib in 1:n_bvecs
            ik2 = kpb_k[ib, ik]

            U₁ = U[:, :, ik]
            U₂ = U[:, :, ik2]

            N[:, :, ib, ik] = U₁' * M[:, :, ib, ik] * U₂
        end
    end

    return N
end

"""
Is matrix unitary or semi-unitary for all the kpoints?
i.e. does it have orthogonal columns?
"""
function isunitary(A::AbstractArray{T,3}; atol::Real=1e-10) where {T<:Number}
    n_bands, n_wann, n_kpts = size(A)

    for ik in 1:n_kpts
        Aₖ = @view A[:, :, ik]
        if norm(Aₖ' * Aₖ - I) > atol
            @debug "not unitary" ik norm(Aₖ' * Aₖ - I)
            return false
        end
    end
    return true
end

function get_projectability(A::AbstractArray{T,3}) where {T<:Number}
    n_bands, n_wann, n_kpts = size(A)
    P = zeros(T, n_bands, n_kpts)
    for ik in 1:n_kpts
        p = A[:, :, ik] * A[:, :, ik]'
        P[:, ik] = real(diag(p))
    end
    return P
end

"""Find vector in the columns of a matrix"""
function findvector(predicate::Function, v::AbstractVector, M::AbstractMatrix)
    for (i, col) in enumerate(eachcol(M))
        predicate(v, col) && return i
    end
    error("$v not found in array!")
    return nothing
end
