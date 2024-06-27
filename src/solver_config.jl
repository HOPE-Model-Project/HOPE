function initiate_solver(solver_name::String, path::String)
	solver_settings = YAML.load(open(path*"Settings/"*solver_name*"_settings.yml"))
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
	if solver_name == "clp"
			# Optional solver parameters ############################################
			Myfeasib_Tol = 1e-7
				if(haskey(solver_settings, "Feasib_Tol")) Myfeasib_Tol = solver_settings["Feasib_Tol"] end
			Myseconds = -1
				if(haskey(solver_settings, "TimeLimit")) Myseconds = solver_settings["TimeLimit"] end
			Mypre_solve = 0
				if(haskey(solver_settings, "Pre_Solve")) Mypre_solve = solver_settings["Pre_Solve"] end
			Mymethod = 5
				if(haskey(solver_settings, "Method")) Mymethod = solver_settings["Method"] end
			MyDualObjectiveLimit = 1e308
				if(haskey(solver_settings, "DualObjectiveLimit")) MymaxNodes = solver_settings["DualObjectiveLimit"] end
			MyMaximumIterations = 2147483647
				if(haskey(solver_settings, "MaximumIterations")) MyallowableGap = solver_settings["MaximumIterations"] end
			MyLogLevel= 1 
				if(haskey(solver_settings, "LogLevel")) MyLogLevel = solver_settings["LogLevel"] end
			MyInfeasibleReturn = 0
				if(haskey(solver_settings, "InfeasibleReturn")) MyInfeasibleReturn = solver_settings["InfeasibleReturn"] end
			MyScaling = 3
				if(haskey(solver_settings, "Scaling")) MyScaling = solver_settings["Scaling"] end
			MyPerturbation = 100
				if(haskey(solver_settings, "Perturbation")) MyPerturbation = solver_settings["Perturbation"] end

			OPTIMIZER = optimizer_with_attributes(Clp.Optimizer,
				"PrimalTolerance" => Myfeasib_Tol,
				"DualObjectiveLimit" => MyDualObjectiveLimit,
				"MaximumIterations" => MyMaximumIterations,
				"MaximumSeconds" => Myseconds,
				"LogLevel" => MyLogLevel,
				"PresolveType" => Mypre_solve,
				"SolveType" => Mymethod,
				"InfeasibleReturn" => MyInfeasibleReturn,
				"Scaling" => MyScaling,
				"Perturbation" => MyPerturbation
			)
	end

	if solver_name == "highs"
		# Optional solver parameters ############################################
		Myfeasib_Tol = 1e-6
			if(haskey(solver_settings, "Feasib_Tol")) Myfeasib_Tol = solver_settings["Feasib_Tol"] end
		MyOptimal_Tol = 1e-4
			if(haskey(solver_settings, "Optimal_Tol")) MyOptimal_Tol = solver_settings["Optimal_Tol"] end
		Myseconds = 1.0e23
			if(haskey(solver_settings, "TimeLimit")) Myseconds = solver_settings["TimeLimit"] end
		Mypre_solve = "choose"
			if(haskey(solver_settings, "Pre_Solve")) Mypre_solve = solver_settings["Pre_Solve"] end
		Mymethod = "ipm"
			if(haskey(solver_settings, "Method")) Mymethod = solver_settings["Method"] end

		OPTIMIZER = optimizer_with_attributes(HiGHS.Optimizer,
			"primal_feasibility_tolerance" => Myfeasib_Tol,
			"dual_feasibility_tolerance" => MyOptimal_Tol,
			"time_limit" => Myseconds,
			"presolve" => Mypre_solve,
			"solver" => Mymethod
		)
	end

	if solver_name == "scip"
		# Optional solver parameters ############################################
		MyDispverblevel = 0
			if(haskey(solver_settings, "Dispverblevel")) MyDispverblevel = solver_settings["Dispverblevel"] end
		Mylimitsgap = 0.05
			if(haskey(solver_settings, "limitsgap")) Mylimitsgap = solver_settings["limitsgap"] end

		OPTIMIZER = optimizer_with_attributes(SCIP.Optimizer,
			"display_verblevel" => MyDispverblevel,
			"limits_gap" => Mylimitsgap
		)
	end

	if solver_name == "cplex"
		# Optional solver parameters ############################################
		Myfeasib_Tol = 1e-7 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-solution-type-lp-qp
			if(haskey(solver_settings, "Feasib_Tol")) Myfeasib_Tol = solver_settings["Feasib_Tol"] end
		MyOptimal_Tol = 1e-4 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-optimality-tolerance
			if(haskey(solver_settings, "Optimal_Tol")) MyOptimal_Tol = solver_settings["Optimal_Tol"] end
		MyAggFill= 10 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-preprocessing-aggregator-fill
			if(haskey(solver_settings, "AggFill")) MyAggFill = solver_settings["AggFill"] end	
		Mypre_dual = 0 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-presolve-dual-setting
			if(haskey(solver_settings, "PreDual")) Mypre_dual = solver_settings["PreDual"] end
		Myseconds = 1e+75 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-optimizer-time-limit-in-seconds
			if(haskey(solver_settings, "TimeLimit")) Myseconds = solver_settings["TimeLimit"] end
		MyMIPGap = 1e-3 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-relative-mip-gap-tolerance
			if(haskey(solver_settings, "MIPGap")) MyMIPGap = solver_settings["MIPGap"] end
		Mymethod = 0 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=optimizers-using-parallel-in-component-libraries
			if(haskey(solver_settings, "Method")) Mymethod = solver_settings["Method"] end
		Mypre_solve = 1 # https://www.ibm.com/docs/en/icos/12.8.0.0?topic=parameters-presolve-switch
			if(haskey(solver_settings, "Pre_Solve")) Mypre_solve = solver_settings["Pre_Solve"] end
		MyBarConvTol = 1e-8 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-convergence-tolerance-lp-qp-problems
			if(haskey(solver_settings, "BarConvTol")) MyBarConvTol = solver_settings["BarConvTol"] end
		MyNumericFocus = 0 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-numerical-precision-emphasis
			if(haskey(solver_settings, "NumericFocus")) MyNumericFocus = solver_settings["NumericFocus"] end
		MyBarObjRng = 1e+75 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-barrier-objective-range
			if(haskey(solver_settings, "BarObjRng")) MyBarObjRng = solver_settings["BarObjRng"] end
		MySolutionType = 2 #https://www.ibm.com/docs/en/cofz/12.9.0?topic=parameters-solution-type-lp-qp
			if(haskey(solver_settings, "SolutionType")) MySolutionType = solver_settings["SolutionType"] end

		OPTIMIZER = optimizer_with_attributes(CPLEX.Optimizer,
			"CPX_PARAM_EPRHS" => Myfeasib_Tol,
            "CPX_PARAM_EPOPT" => MyOptimal_Tol,
            "CPX_PARAM_AGGFILL" => MyAggFill,
            "CPX_PARAM_PREDUAL" => Mypre_dual,
            "CPX_PARAM_TILIM" => Myseconds,
            "CPX_PARAM_EPGAP" => MyMIPGap,
            "CPX_PARAM_LPMETHOD" => Mymethod,
			"CPX_PARAM_PREIND" => Mypre_solve,
            "CPX_PARAM_BAREPCOMP" => MyBarConvTol,
            "CPX_PARAM_NUMERICALEMPHASIS" => MyNumericFocus,
            "CPX_PARAM_BAROBJRNG" => MyBarObjRng,
            "CPX_PARAM_SOLUTIONTYPE" => MySolutionType
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
