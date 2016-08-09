# TODO: better names for the functions

function updatecoeffs!{T<:Real}(coeff0, coeff1, coeff2, rhs, model, v, t::T, x,
                                a::T, Δτ::T, Δx::T)
    # TODO: should we just remove this dispatch and pass in ones(n-2)*a instead?
    # Updates
    # coeffn = values in linear system
    # rhs    = value function at previous timestep + f at current timestep

    # Input
    # model  = HJBOneDim object
    # v      = value function at previous timestep
    # t      = value of (forward) time
    # x      = vector of x-values
    # a      = policy-values on interior
    # Δτ     = time-step size
    # Δx     = spacial step length
    taux = Δτ/Δx
    htaux2 = 0.5*Δτ/Δx^2

    n = length(coeff0)
    for j = 2:n-1
        @inbounds begin
            bval = model.b(t,x[j],a)
            sval2 = model.σ(t,x[j],a)^2
            coeff1[j] = -(sval2*htaux2 + max(bval,0.)*taux)
            coeff2[j-1] = -(sval2*htaux2 - min(bval,0.)*taux)
            coeff0[j] = 1.-coeff1[j]-coeff2[j-1]
            rhs[j] = v[j] + Δτ*model.f(t,x[j],a)
        end
    end
end

function policytimestep(model::HJBOneDim,
                        v, avals, x, Δx, Δτ, ti::Int)
    t = model.T - ti*Δτ
    n = length(x)

    # TODO: redo this thing
    newind = ones(Int, n)
    @inbounds vnew = -maxintfloat(typeof(x[1]))*ones(x)

    ind12 = zeros(Bool, length(vnew))

    coeff0 = ones(x)   # v_i
    coeff1 = zeros(n-1) # v_{i+1} # TODO: type stability
    coeff2 = zeros(n-1) # v_{i-1} # TODO: type stability
    rhs = zeros(x)
    # Dirichlet conditions
    @inbounds rhs[1] = model.Dmin(t, x[1])
    @inbounds rhs[end] = model.Dmax(t, x[end])

    for i = 1:length(avals)
        @inbounds begin
            a = avals[i]
            vold = vnew

            updatecoeffs!(coeff0, coeff1, coeff2, rhs, model, v, t, x, a, Δτ, Δx)

            Mat = spdiagm((coeff2, coeff0, coeff1), -1:1, n, n)

            # TODO: Use Krylov solver for high-dimensional PDEs
            vnew = Mat\rhs

            ind12[:] = vold .> vnew
            vnew[ind12] = vold[ind12]
            newind[!ind12] = i
        end
    end
    # newind[1,end] represent boundaries, no control is used there
    @inbounds pol = avals[newind[2:end-1]]

    return vnew, pol
end


function timeloopconstant(model::HJBOneDim, K::Int, N::Int,
                          Δτ, vinit, avals, x, Δx)
    # Pass v and pol by reference?
    v = zeros(K+1, N+1)
    pol = zeros(K-1, N) # No policy at t = T or at x-boundaries

    @inbounds v[:,1] = vinit # We use forward time t instead of backward time τ

    for j = 1:N
        @inbounds begin
            # t = (N-j)*Δτ
            # TODO: pass v-column, pol-column by reference?
            v[:,j+1], pol[:,j] = policytimestep(model, v[:, j],
                                                avals, x, Δx, Δτ, j)
        end
    end

    return v, pol
end
