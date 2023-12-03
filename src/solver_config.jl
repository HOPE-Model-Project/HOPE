"""

 - seconds = 1e-6
 - logLevel = 1e-6
 - maxSolutions = -1
 - maxNodes = -1
 - allowableGap = -1
 - ratioGap = Inf
 - threads = 1

"""
function initiate_solver(solver_name::String)
	solver_settings = YAML.load(open("Settings/"*solver_name*"_settings.yml"))
	if solver_name == "cbc"
			# Optional solver parameters ############################################
		Myseconds = 1e-6
			if(haskey(solver_settings, "TimeLimit")) Myseconds = solver_settings["TimeLimit"] end
		MylogLevel = 1e-6
			if(haskey(solver_settings, "logLevel")) MylogLevel = solver_settings["logLevel"] end
		MymaxSolutions = -1
			if(haskey(solver_settings, "maxSolutions")) MymaxSolutions = solver_settings["maxSolutions"] end
		MymaxNodes = -1
			if(haskey(solver_settings, "maxNodes")) MymaxNodes = solver_settings["maxNodes"] end
		MyallowableGap = -1
			if(haskey(solver_settings, "allowableGap")) MyallowableGap = solver_settings["allowableGap"] end
		MyratioGap = Inf
			if(haskey(solver_settings, "ratioGap")) MyratioGap = solver_settings["ratioGap"] end
		Mythreads = 1
			if(haskey(solver_settings, "threads")) Mythreads = solver_settings["threads"] end
		########################################################################

		OPTIMIZER = optimizer_with_attributes(Cbc.Optimizer,
			"seconds" => Myseconds,
			"logLevel" => MylogLevel,
			"maxSolutions" => MymaxSolutions,
			"maxNodes" => MymaxNodes,
			"allowableGap" => MyallowableGap,
			"ratioGap" => MyratioGap,
			"threads" => Mythreads
		)
	end
	if solver_name == "gurobi"
		# Optional solver parameters ############################################
		MyFeasibilityTol = 1e-6 # Constraint (primal) feasibility tolerances. See https://www.gurobi.com/documentation/8.1/refman/feasibilitytol.html
			if(haskey(solver_settings, "Feasib_Tol")) MyFeasibilityTol = solver_settings["Feasib_Tol"] end
		MyOptimalityTol = 1e-4 # Dual feasibility tolerances. See https://www.gurobi.com/documentation/8.1/refman/optimalitytol.html#parameter:OptimalityTol
			if(haskey(solver_settings, "Optimal_Tol")) MyOptimalityTol = solver_settings["Optimal_Tol"] end
		MyPresolve = -1 	# Controls presolve level. See https://www.gurobi.com/documentation/8.1/refman/presolve.html
			if(haskey(solver_settings, "Pre_Solve")) MyPresolve = solver_settings["Pre_Solve"] end
		MyAggFill = -1 		# Allowed fill during presolve aggregation. See https://www.gurobi.com/documentation/8.1/refman/aggfill.html#parameter:AggFill
			if(haskey(solver_settings, "AggFill")) MyAggFill = solver_settings["AggFill"] end
		MyPreDual = -1		# Presolve dualization. See https://www.gurobi.com/documentation/8.1/refman/predual.html#parameter:PreDual
			if(haskey(solver_settings, "PreDual")) MyPreDual = solver_settings["PreDual"] end
		MyTimeLimit = Inf	# Limits total time solver. See https://www.gurobi.com/documentation/8.1/refman/timelimit.html
			if(haskey(solver_settings, "TimeLimit")) MyTimeLimit = solver_settings["TimeLimit"] end
		MyMIPGap = 1e-3		# Relative (p.u. of optimal) mixed integer optimality tolerance for MIP problems (ignored otherwise). See https://www.gurobi.com/documentation/8.1/refman/mipgap2.html
			if(haskey(solver_settings, "MIPGap")) MyMIPGap = solver_settings["MIPGap"] end
		MyCrossover = -1 	# Barrier crossver strategy. See https://www.gurobi.com/documentation/8.1/refman/crossover.html#parameter:Crossover
			if(haskey(solver_settings, "Crossover")) MyCrossover = solver_settings["Crossover"] end
		MyMethod = -1		# Algorithm used to solve continuous models (including MIP root relaxation). See https://www.gurobi.com/documentation/8.1/refman/method.html
			if(haskey(solver_settings, "Method")) MyMethod = solver_settings["Method"] end
		MyBarConvTol = 1e-8 	# Barrier convergence tolerance (determines when barrier terminates). See https://www.gurobi.com/documentation/8.1/refman/barconvtol.html
			if(haskey(solver_settings, "BarConvTol")) MyBarConvTol = solver_settings["BarConvTol"] end
		MyNumericFocus = 0 	# Numerical precision emphasis. See https://www.gurobi.com/documentation/8.1/refman/numericfocus.html
			if(haskey(solver_settings, "NumericFocus")) MyNumericFocus = solver_settings["NumericFocus"] end
		MyOutputFlag = 1 	# Controls Gurobi output. See https://www.gurobi.com/documentation/8.1/refman/numericfocus.html
			if(haskey(solver_settings, "OutputFlag")) MyOutputFlag = solver_settings["OutputFlag"] end
		########################################################################

		OPTIMIZER = optimizer_with_attributes(Gurobi.Optimizer,
			"OptimalityTol" => MyOptimalityTol,
			"FeasibilityTol" => MyFeasibilityTol,
			"Presolve" => MyPresolve,
			"AggFill" => MyAggFill,
			"PreDual" => MyPreDual,
			"TimeLimit" => MyTimeLimit,
			"MIPGap" => MyMIPGap,
			"Method" => MyMethod,
			"BarConvTol" => MyBarConvTol,
			"NumericFocus" => MyNumericFocus,
			"Crossover" =>  MyCrossover,
			"OutputFlag" => MyOutputFlag
		)
	end
	return OPTIMIZER
end
