export linear_region, linear_regions, estimate_boxsizes, linreg
export boxcounting_dim, capacity_dim, generalized_dim,
information_dim, estimate_boxsizes, kaplanyorke_dim
#####################################################################################
# Functions and methods to deduce linear scaling regions
#####################################################################################
using Statistics
using Statistics: covm, varm
# The following function comes from a version in StatsBase that is now deleted
# StatsBase is copyrighted under the MIT License with
# Copyright (c) 2012-2016: Dahua Lin, Simon Byrne, Andreas Noack, Douglas Bates,
# John Myles White, Simon Kornblith, and other contributors.
"""
    linreg(x, y) -> a, b
Perform a linear regression to find the best coefficients so that the curve:
`y = a + b*x` has the least squared error.
"""
function linreg(x::AbstractVector, y::AbstractVector)
    # Least squares given
    # Y = a + b*X
    # where
    # b = cov(X, Y)/var(X)
    # a = mean(Y) - b*mean(X)
    if size(x) != size(y)
        throw(DimensionMismatch("x has size $(size(x)) and y has size $(size(y)), " *
            "but these must be the same size"))
    end
    mx = Statistics.mean(x)
    my = Statistics.mean(y)
    # don't need to worry about the scaling (n vs n - 1)
    # since they cancel in the ratio
    b = covm(x, mx, y, my)/varm(x, mx)
    a = my - b*mx
    return a, b
end

slope(x, y) = linreg(x, y)[2]

"""
    linear_region(x, y; dxi::Int = 1, tol = 0.2) -> ([ind1, ind2], slope)
Call [`linear_regions`](@ref), identify the largest linear region
and approximate the slope of the entire region using `linreg`.
Return the indices where
the region starts and stops (`x[ind1:ind2]`) as well as the approximated slope.
"""
function linear_region(x::AbstractVector, y::AbstractVector;
    dxi::Int = 1, tol::Real = 0.2)

    # Find biggest linear region:
    reg_ind = max_linear_region(linear_regions(x,y; dxi=dxi, tol=tol)...)
    # least squares fit:
    xfit = view(x, reg_ind[1]:reg_ind[2])
    yfit = view(y, reg_ind[1]:reg_ind[2])
    approx_tang = slope(xfit, yfit)
    return reg_ind, approx_tang
end

"""
    max_linear_region(lrs::Vector{Int}, tangents::Vector{Float64})
Find the biggest linear region and return it.
"""
function max_linear_region(lrs::Vector{Int}, tangents::Vector{Float64})
    dis = 0
    tagind = 0
    for i in 1:length(lrs)-1
        if lrs[i+1] - lrs[i] > dis
            dis = lrs[i+1] - lrs[i]
            tagind = i
        end
    end
    return [lrs[tagind], lrs[tagind+1]]
end

"""
    linear_regions(x, y; dxi::Int = 1, tol = 0.2) -> (lrs, tangents)
Identify regions where the curve `y(x)` is linear, by scanning the
`x`-axis every `dxi` indices (e.g. at `x[1] to x[5], x[5] to x[10], x[10] to x[15]`
and so on if `dxi=5`).

If the slope (calculated using `LsqFit`) of a region of width `dxi` is
approximatelly equal to that of the previous region,
within tolerance `tol`,
then these two regions belong to the same linear region.

Return the indices of `x` that correspond to linear regions, `lrs`,
and the approximated `tangents` at each region. `lrs` is a vector of `Int`.
Notice that `tangents` is _not_ accurate: it is not recomputed at every step,
but only when its error exceeds the tolerance `tol`! Use [`linear_region`](@ref)
to obtain a correct estimate for the slope of the largest linear region.
"""
function linear_regions(x::AbstractVector, y::AbstractVector;
    dxi::Int = 1, tol::Real = 0.2)

    maxit = length(x) ÷ dxi

    tangents = Float64[slope(view(x, 1:max(dxi, 2)), view(y, 1:max(dxi, 2)))]

    prevtang = tangents[1]
    lrs = Int[1] #start of first linear region is always 1
    lastk = 1

    # Start loop over all partitions of `x` into `dxi` intervals:
    for k in 1:maxit-1
        # tang = linreg(view(x, k*dxi:(k+1)*dxi), view(y, k*dxi:(k+1)*dxi))[2]
        tang = slope(view(x, k*dxi:(k+1)*dxi), view(y, k*dxi:(k+1)*dxi))
        if isapprox(tang, prevtang, rtol=tol)
            # Tanget is similar with initial previous one (based on tolerance)
            continue
        else
            # Tangent is not similar.
            # Push new tangent for a new linear region
            push!(tangents, tang)

            # Set the START of a new linear region
            # which is also the END of the previous linear region
            push!(lrs, k*dxi)
            lastk = k
        end

        # Set new previous tangent (only if it was not the same as current)
        prevtang = tang
    end
    push!(lrs, length(x))
    return lrs, tangents
end


#######################################################################################
# Dimensions
#######################################################################################
"""
    estimate_boxsizes(dataset::AbstractDataset; k::Int = 12, z = -1, w = 1)
Return `k` exponentially spaced values: `10 .^ range(lower+w, upper+z, length = k)`.

`lower` is the magnitude of the
minimum pair-wise distance between datapoints while `upper` is the magnitude
of the maximum difference between
greatest and smallest number among each timeseries.

"Magnitude" here stands for order of magnitude, i.e. `round(log10(x))`.
"""
function estimate_boxsizes(data::AbstractDataset{D, T};
    k::Int = 12, z = -1.0, w = 1.0) where {D, T<:Number}

    mi, ma = minmaxima(data)
    upper = round(log10(maximum(ma - mi)))

    mindist = min_pairwise_distance(data)[2]
    lower = ceil(log10(mindist)) # ceil necessary to not use smaller distance.

    if lower ≥ upper
        error(
        "Boxsize estimation failed: `upper` was found ≥ than "*
        "`lower`. Adjust keywords or provide a bigger dataset.")
    end
    if lower + w + 2 ≥ upper + z
        @warn "Boxsizes limits do not differ by 2 orders of magnitude or more. "*
        "Setting `w -= 0.5; z += 0.5`. Please adjust keywords or provide a bigger dataset."
        w -= 0.5; z += 0.5
    end

    return 10.0 .^ range(lower+w, stop = upper+z, length = k)
end

estimate_boxsizes(ts::AbstractMatrix; kwargs...) =
estimate_boxsizes(convert(Dataset, ts); kwargs...)

"""
    generalized_dim(α, dataset [, sizes]) -> D_α
Return the `α` order generalized dimension of the `dataset`, by calculating
the [`genentropy`](@ref) for each `ε ∈ sizes`.

## Description
The returned dimension is approximated by the
(inverse) power law exponent of the scaling of the [`genentropy`](@ref)
versus the box size `ε`, where `ε ∈ sizes`.

Calling this function performs a lot of automated steps:

  1. A vector of box sizes is decided by calling `sizes = estimate_boxsizes(dataset)`,
     if `sizes` is not given.
  2. For each element of `sizes` the appropriate entropy is
     calculated, through `d = genentropy.(α, sizes, dataset)`.
     Let `x = -log.(sizes)`.
  3. The curve `d(x)` is decomposed into linear regions,
     using [`linear_regions`](@ref)`(x, d)`.
  4. The biggest linear region is chosen, and a fit for the slope of that
     region is performed using the function [`linear_region`](@ref).
     This slope is the return value of `generalized_dim`.

By doing these steps one by one yourself, you can adjust the keyword arguments
given to each of these function calls, refining the accuracy of the result.

The following aliases are provided:

  * α = 0 : `boxcounting_dim`, `capacity_dim`
  * α = 1 : `information_dim`
"""
function generalized_dim(α, data::AbstractDataset, sizes = estimate_boxsizes(data))
    dd = genentropy.(α, sizes, Ref(data))
    return linear_region(-log.(sizes), dd)[2]
end
generalized_dim(α, matrix::AbstractMatrix, args...) =
generalized_dim(α, convert(AbstractDataset, matrix), args...)

# Aliases
"capacity_dim(args...) = generalized_dim(0, args...)"
capacity_dim(args...) = generalized_dim(0, args...)
boxcounting_dim = capacity_dim

"information_dim(args...) = generalized_dim(1, args...)"
information_dim(args...) = generalized_dim(1, args...)



"""
    kaplanyorke_dim(lyapunovs::AbstractVector)
Calculate the Kaplan-Yorke dimension, a.k.a. Lyapunov dimension [1].

## Description
The Kaplan-Yorke dimension is simply the point where
`cumsum(lyapunovs)` becomes zero (interpolated). If
the sum of the exponents never becomes negative the function
will return the length of the input vector.

Useful in combination with [`lyapunovs`](@ref).

## References

[1] :  J. Kaplan & J. Yorke,
*Chaotic behavior of multidimensional difference equations*,
Lecture Notes in Mathematics vol. **730**, Springer (1979)
"""
function kaplanyorke_dim(v::AbstractVector)
    issorted(v, rev = true) || throw(ArgumentError(
    "The lyapunov vector must be sorted from most positive to most negative"))

    s = cumsum(v); k = length(v)
    # Find k such that sum(λ_i for i in 1:k) is still possitive
    for i in eachindex(s)
        if s[i] < 0
            k = i-1
            break
        end
    end

    if k == 0
        return zero(v[1])
    elseif k < length(v)
        return k + s[k]/abs(v[k+1])
    else
        return typeof(v[1])(length(v))
    end
end
