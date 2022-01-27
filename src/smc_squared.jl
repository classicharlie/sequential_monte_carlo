# this only works with particles that are Vector{Float64}
function randomWalk(θ::Particles,c::Float64=0.5)
    k = length(θ.x[1])
    M = length(θ.x)
    x = reduce(hcat,θ.x)

    # calculate the weighted mean
    μ = [(sum(θ.w .* x[i,:]))/sum(θ.w) for i in 1:k]
    
    # calculate the weighted covariance (please double check)
    adjx = [x[:,m] - μ for m in 1:M]
    Σ = sum(θ.w[m]*adjx[m]*adjx[m]' for m in 1:M)/sum(w)
    # Σ = StatsBase.cov(x,μ,θ.w)

    # finish this to generate a particle set
    newθ = rand(MvNormal(μ,c*Σ),M)
    return Particles([newθ[:,m] for m in 1:M])
end

function randomWalkMH(
        t::Int64,
        θ::Particles,
        Xt::Vector{Particles},
        N::Int64,
        prior::Function,
        c::Float64=0.5,
        chain::Int64=10
    )

    # consider whether I should do this per particle or over the whole set
    k = length(θ.x[1])
    M = length(θ.x)

    for _ in 1:chain
        newθ = randomWalk(θ,c)
        newΘ = [StateSpaceModel(model(newθ.x[m]...)) for m in 1:M]

        # perform another PF from 1:t and OPTIMIZE THIS
        newx0 = (newΘ[1].dim_x == 1) ? 0.0 : zeros(Float64,newΘ[1].dim_x)
        newXt = [Particles(rand(newΘ[m].transition(newx0),N)) for m in 1:M]

        for k in 1:t
            newXt = bootstrapStep(k,newΘ,N,y,newXt,B)
            newθ  = reweight(newθ,newθ.logw+[newXt[m].logμ for m in 1:M])
        end

        # Z(θ) ≡ likelihood, p(θ) ≡ pdf of prior
        logZt = Xt.logμ-newXt.logμ
        logpt = logpdf(prior,θ)-logpdf(prior,newθ)

        # acceptance ratio
        α = exp(logZt+logpt)
        u = rand()

        if u ≤ α
            θ  = newθ
            Xt = newXt
        end
    end

    return θ,Xt
end

function bootstrapStep(
        t::Int64,
        Θ::Vector{StateSpaceModel},
        N::Int64,
        y::Vector{Float64},
        Xt::Vector{Particles},
        B::Float64
    )
    M = length(Xt)

    for m in 1:M
        xt = rand.(Θ[m].transition.(Xt[m].x),N)
        wt = logpdf.(Θ[m].observation.(xt),y[t])
        Xt[m] = resample(Particles(xt,wt),B)
    end

    return Xt
end

# Base function for SMC² which takes a Particles object as input
function SMC2(
        N::Int64,
        M::Int64,
        y::Vector{Float64},
        θ::Particles,
        prior::Function,
        B::Float64 = 0.5,
        model = LinearGaussian
    )
    T = length(y)
    
    Θ  = [StateSpaceModel(model(θ.x[m]...)) for m in 1:M]
    x0 = (Θ[1].dim_x == 1) ? 0.0 : zeros(Float64,Θ[1].dim_x)
    Xt = [Particles(rand(Θ[m].transition(x0),N)) for m in 1:M]

    # perform iteration t of the bootstrap filter and reweight θ particles
    for t in ProgressBar(1:T)
        Xt = bootstrapStep(t,Θ,N,y,Xt,B)
        θ  = reweight(θ,θ.logw+[Xtm.logμ for Xtm in Xt])
        
        # perform MH steps in case of degeneracy of θ particles
        if θ.ess < B*M
            θ = randomWalkMH(t,θ,Xt,N,prior,0.5,5)
        end
    end

    return θ
end

# this is a wrapper given a guess for the initial state θ_0
function SMC2(
        N::Int64,
        M::Int64,
        y::Vector{Float64},
        θ0::Vector{Float64},
        prior::Function,
        B::Float64 = 0.5,
        model = LinearGaussian
    )
    k = length(θ0)

    θ = rand(prior(θ0,Matrix{Float64}(I,k,k)),M)
    θ = Particles([θ[:,m] for m in 1:M])

    return SMC2(N,M,y,θ,prior,B,model)
end