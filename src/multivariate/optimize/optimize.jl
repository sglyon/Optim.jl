
update_g!(d, state, method) = nothing
function update_g!(d, state, method::M) where M<:Union{FirstOrderSolver, Newton}
    # Update the function value and gradient
    value_gradient!(d, state.x)
end

# Update the Hessian
update_h!(d, state, method) = nothing
update_h!(d, state, method::SecondOrderSolver) = hessian!(d, state.x)

after_while!(d, state, method, options) = nothing

function optimize(d::D, initial_x::AbstractArray, method::M,
    options::Options = Options(), state = initial_state(method, options, d, initial_x)) where {D<:AbstractObjective, M<:Optimizer}

    t0 = time() # Initial time stamp used to control early stopping by options.time_limit

    if length(initial_x) == 1 && typeof(method) <: NelderMead
        error("Use optimize(f, scalar, scalar) for 1D problems")
    end

    n = length(initial_x)
    tr = OptimizationTrace{typeof(method)}()
    tracing = options.store_trace || options.show_trace || options.extended_trace || options.callback != nothing
    stopped, stopped_by_callback, stopped_by_time_limit = false, false, false
    f_limit_reached, g_limit_reached, h_limit_reached = false, false, false
    x_converged, f_converged, f_increased = false, false, false
    g_converged = if typeof(method) <: NelderMead
        nmobjective(state.f_simplex, state.m, n) < options.g_tol
    elseif  typeof(method) <: ParticleSwarm || typeof(method) <: SimulatedAnnealing
        g_converged = false
    else
        vecnorm(gradient(d), Inf) < options.g_tol
    end

    converged = g_converged
    iteration = 0

    options.show_trace && print_header(method)
    trace!(tr, d, state, iteration, method, options)

    while !converged && !stopped && iteration < options.iterations
        iteration += 1

        update_state!(d, state, method) && break # it returns true if it's forced by something in update! to stop (eg dx_dg == 0.0 in BFGS)
        update_g!(d, state, method)
        x_converged, f_converged,
        g_converged, converged, f_increased = assess_convergence(state, d, options)

        !converged && update_h!(d, state, method) # only relevant if not converged

        if tracing
            # update trace; callbacks can stop routine early by returning true
            stopped_by_callback = trace!(tr, d, state, iteration, method, options)
        end

        stopped_by_time_limit = time()-t0 > options.time_limit ? true : false
        f_limit_reached = options.f_calls_limit > 0 && f_calls(d) >= options.f_calls_limit ? true : false
        g_limit_reached = options.g_calls_limit > 0 && g_calls(d) >= options.g_calls_limit ? true : false
        h_limit_reached = options.h_calls_limit > 0 && h_calls(d) >= options.h_calls_limit ? true : false

        if (f_increased && !options.allow_f_increases) || stopped_by_callback ||
            stopped_by_time_limit || f_limit_reached || g_limit_reached || h_limit_reached
            stopped = true
        end
    end # while

    after_while!(d, state, method, options)

    try
    return MultivariateOptimizationResults(method,
                                            initial_x,
                                            f_increased ? state.x_previous : state.x,
                                            f_increased ? state.f_x_previous : value(d),
                                            iteration,
                                            iteration == options.iterations,
                                            x_converged,
                                            options.x_tol,
                                            x_residual(state.x, state.x_previous),
                                            f_converged,
                                            options.f_tol,
                                            f_residual(value(d), state.f_x_previous, options.f_tol),
                                            g_converged,
                                            options.g_tol,
                                            g_residual(gradient(d)),
                                            f_increased,
                                            tr,
                                            f_calls(d),
                                            g_calls(d),
                                            h_calls(d))
    catch
      return MultivariateOptimizationResults(method,
                                              initial_x,
                                              f_increased ? state.x_previous : state.x,
                                              f_increased ? state.f_x_previous : value(d),
                                              iteration,
                                              iteration == options.iterations,
                                              x_converged,
                                              options.x_tol,
                                              NaN,
                                              f_converged,
                                              options.f_tol,
                                              NaN,
                                              g_converged,
                                              options.g_tol,
                                              NaN,
                                              f_increased,
                                              tr,
                                              f_calls(d),
                                              g_calls(d),
                                              h_calls(d))
    end

end
