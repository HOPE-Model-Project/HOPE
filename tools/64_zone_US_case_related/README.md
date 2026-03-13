# USA 64-Zone Case Processing Scripts

This folder contains processing and utility scripts specific to the USA 64-zone GTEP case.

- `convert_genx_usa64_to_hope_gtep.jl`: convert GenX-formatted USA64 inputs into HOPE multi-CSV case inputs.
- `run_usa64_case.jl`: run the USA64 case through `HOPE.run_hope`.
- `diagnose_usa64_infeasibility.jl`: build/solve and run conflict refinement diagnostics.
- `validate_usa64_external_weights.jl`: validate external representative-period input loading and model build.
- `generate_usa64_maps.jl`: generate USA64 existing/buildout SVG maps for docs.
