# HOPE New Architecture - Redesigned for Extensibility and Transparency

This directory contains the redesigned HOPE architecture featuring modular, extensible, and transparent design patterns.

## 🏗️ Architecture Overview

The new architecture is organized into distinct layers for maximum modularity:

```
src_new/
├── core/                    # Core architecture components
│   ├── ConstraintPool.jl    # Unified constraint management
│   ├── ConstraintImplementations.jl  # Specific constraint functions  
│   ├── TimeManager.jl       # Time index harmonization
│   └── ModelBuilder.jl      # Model construction framework
├── io/                      # Input/Output layer
│   ├── DataReader.jl        # Standardized data loading
│   ├── DataWriter.jl        # Standardized output writing (planned)
│   └── DataValidator.jl     # Input validation (planned)
├── models/                  # Model-specific implementations
│   ├── GTEP.jl              # Refactored GTEP model (planned)
│   ├── PCM.jl               # Refactored PCM model (planned)
│   └── HolisticWorkflow.jl  # GTEP→PCM workflow (planned)
├── utils/                   # Utilities and management
│   ├── PlotManager.jl       # Unified plotting (planned)
│   ├── SolverManager.jl     # Solver configuration (planned)
│   └── ConfigManager.jl     # Settings management (planned)
└── HOPE_New.jl              # Main entry point
```

## 🌟 Key Features

### 1. **Constraint Pool System**
- **Unified Management**: All constraints in one centralized pool
- **Automatic Categorization**: Constraints grouped by type (power balance, investment, policy, etc.)
- **Model-Agnostic**: Same constraints work across GTEP, PCM, and holistic modes
- **Conditional Application**: Constraints applied based on configuration settings
- **Transparent Reporting**: Detailed constraint status and violation reporting

### 2. **Time Index Harmonization**
- **Flexible Time Structures**: Support for GTEP representative days and PCM full-year
- **Automatic Mapping**: Seamless conversion between different time representations
- **Holistic Integration**: Direct mapping from GTEP planning to PCM operation
- **Consistent Scaling**: Proper temporal scaling for annual calculations

### 3. **Standardized Input/Output**
- **Unified Data Loading**: Consistent data reading across all model types
- **Automatic Validation**: Built-in data consistency and completeness checks
- **Flexible Formats**: Support for CSV, Excel, and other data formats
- **Error Handling**: Graceful handling of missing or invalid data

### 4. **Modular Model Building**
- **Component-Based**: Variables, constraints, and objectives as separate modules
- **Configuration-Driven**: Model features controlled by settings
- **Extensible Design**: Easy to add new constraints, variables, or model types
- **Debug-Friendly**: Built-in debugging and introspection capabilities

## 🚀 Quick Start

### Basic Usage

```julia
# Add src_new to path
push!(LOAD_PATH, "path/to/HOPE/src_new")

# Load new architecture
include("HOPE_New.jl")
using .HOPE_New

# Run with new architecture
result = run_hope_new("path/to/case")
model, builder, report = result
```

### Demo Example

```julia
# Run the built-in demo
result = HOPE_New.demo_new_architecture()

# This creates a minimal test case and demonstrates:
# - Constraint pool initialization
# - Time structure management  
# - Model building process
# - Solution and reporting
```

### Advanced Usage

```julia
# Create custom model builder
builder = HOPEModelBuilder()

# Load and configure
reader = HOPEDataReader("case_path")
input_data = load_hope_data(reader)
config = load_configuration(reader)

# Initialize with custom optimizer
using Gurobi
initialize!(builder, config, input_data, Gurobi.Optimizer)

# Build and solve
model = build_model!(builder)
optimize!(model)

# Generate detailed report
report = get_model_report(builder)
```

## 🔧 Configuration

The new architecture uses the same YAML configuration format but with enhanced capabilities:

```yaml
model_mode: "PCM"           # GTEP, PCM, or HOLISTIC
solver: "HiGHS"             # Solver selection
unit_commitment: 1          # Enable unit commitment constraints
flexible_demand: 0          # Enable demand response
debug: 2                    # Debug level (0=none, 1=conflicts, 2=penalties)
investment_binary: 1        # Binary investment decisions (GTEP)
target_year: 2035          # Planning year
```

## 📊 Benefits vs Original Architecture

| Aspect | Original | New Architecture |
|--------|----------|------------------|
| **Constraint Management** | Scattered across files | Centralized constraint pool |
| **Time Handling** | Model-specific | Unified time manager |
| **Data Loading** | Duplicate code | Standardized data reader |
| **Model Building** | Monolithic functions | Modular components |
| **Debugging** | Limited tools | Built-in debug capabilities |
| **Extensibility** | Requires code changes | Configuration-driven |
| **Transparency** | Opaque model building | Step-by-step reporting |
| **Testing** | Difficult to isolate | Component-level testing |

## 🧪 Testing

Run the test suite to verify the architecture:

```julia
include("test_new_architecture.jl")
```

This will:
1. Test the built-in demo with minimal data
2. Verify individual components (constraint pool, time manager, etc.)
3. Test data loading with actual case files (if available)

## 🛠️ Implementation Status

### ✅ Completed
- [x] Constraint pool framework
- [x] Time manager for GTEP/PCM/Holistic modes
- [x] Model builder with variable/constraint/objective creation
- [x] Standardized data reader with validation
- [x] Main entry point and demo functionality
- [x] Test suite and documentation

### 🚧 In Progress  
- [ ] Complete constraint implementations (power balance, investment, policy)
- [ ] Output writing and plotting modules
- [ ] Holistic workflow (GTEP→PCM) implementation
- [ ] Performance optimization

### 📋 Planned
- [ ] Data writer for standardized outputs
- [ ] Plot manager for unified visualization
- [ ] Solver manager for advanced configuration
- [ ] Configuration manager for settings validation
- [ ] Comprehensive test cases
- [ ] Migration guide from old architecture

## 🤝 Contributing

The new architecture is designed for easy contribution:

1. **Adding Constraints**: Register in `ConstraintPool.jl`, implement in `ConstraintImplementations.jl`
2. **New Model Types**: Extend `ModelBuilder.jl` with new variable/constraint patterns  
3. **Data Sources**: Add new loaders to `DataReader.jl`
4. **Utilities**: Add helper functions to appropriate `utils/` modules

## 📚 Documentation

- `HOPE_New.jl`: Main module with high-level functions
- `core/ConstraintPool.jl`: Constraint management system
- `core/TimeManager.jl`: Time structure handling
- `core/ModelBuilder.jl`: Model construction framework
- `io/DataReader.jl`: Data loading and validation

## 🎯 Next Steps

1. **Complete Implementation**: Finish remaining constraint functions and utilities
2. **Testing**: Add comprehensive test coverage for all components
3. **Performance**: Optimize model building and solution times
4. **Documentation**: Create detailed user and developer guides
5. **Migration**: Provide tools to migrate from old to new architecture
6. **Integration**: Merge with main HOPE repository

---

*This new architecture represents a significant improvement in HOPE's modularity, extensibility, and transparency while maintaining full compatibility with existing case files and workflows.*
