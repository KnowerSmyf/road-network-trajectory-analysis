# Road-Network Trajectory Analysis

A reproducible geospatial data pipeline and road-network analysis system built over **1,710,670 Porto taxi trips** and OpenStreetMap road data.

The project combines Python, PostgreSQL, PostGIS and pgRouting to validate GPS trajectories, construct canonical spatial representations, map observations onto a routable street graph and compare journeys using road-network travel costs.

## Current status

The taxi ingestion and validation layer has been rebuilt as a reproducible, tested pipeline and merged into the primary project architecture.

Implemented in the refactor:

* Docker-based PostgreSQL/PostGIS environment;
* reproducible ingestion of the complete Porto taxi dataset;
* explicit staging, rejection and core data models;
* structural and velocity validation;
* persistent rejection reasons and diagnostic details;
* canonical PostGIS `LINESTRING` trajectories;
* Python and SQL assertions;
* row-count reconciliation across pipeline stages;
* Make-based orchestration;
* controlled performance benchmarks.

Next to be migrated from the original implementation:

* OpenStreetMap road-network ingestion;
* pgRouting topology construction;
* GPS-to-road map matching;
* shortest-path routing queries;
* service-station detour analysis;
* network-aware trajectory similarity;
* expanded index and query-plan experiments.

## Motivation

Straight-line distance is often a poor model of movement through a city.

Two GPS observations may be geographically close while lying on opposite sides of a river, motorway barrier or one-way road system. Likewise, two journeys can appear geometrically similar while following meaningfully different routes.

This project therefore analyses trajectories through the underlying road network:

```text
GPS observations
    → road-segment positions
    → shortest-path travel costs
    → ordered trajectory comparison
```

## Current pipeline

```text
Porto taxi CSV
      |
      v
staging.taxi_trips_raw
      |
      v
structural validation
      |
      v
velocity validation
      |
      +--------> staging.trip_rejections
      |
      v
core.trips
```

### Raw ingestion

The source CSV is loaded into a staging schema without immediately transforming or deleting source data.

Each row receives an internal ingestion identifier so that validation results can be tracked independently of source trip identifiers.

### Structural validation

SQL validation records rejected rows and their reasons in `staging.trip_rejections`.

Current checks include:

* source rows marked as containing missing data;
* missing required values;
* invalid categorical values;
* trajectories with insufficient coordinates;
* duplicate trip identifiers;
* degenerate trajectories that cannot form valid line geometries.

Rejected rows remain available in staging for inspection and debugging.

### Velocity validation

Taxi observations are sampled at 15-second intervals.

The Python validator calculates the implied speed between consecutive GPS coordinates and rejects trips containing a segment above 200 km/h. The threshold is intended to detect severe GPS jumps and corrupt observations rather than enforce normal road speed limits.

The original implementation calculated a full pairwise distance matrix for every trajectory. The refactored implementation processes only consecutive observations.

Observed full-dataset performance on the development machine:

| Implementation                              | Approximate runtime |
| ------------------------------------------- | ------------------: |
| Original pairwise implementation            |          30 minutes |
| Refactored consecutive-point implementation |          40 seconds |

Smaller controlled benchmarks also compared:

* reusable scalar Haversine helper;
* inlined scalar calculations;
* vectorised NumPy calculations.

The benchmark showed that the algorithmic redesign produced the overwhelming majority of the improvement. Inlining reduced scalar runtime by approximately 28%, while NumPy provided a further improvement of approximately 4% over the inlined scalar implementation.

See `docs/velocity-validation.md` for methodology and results.

### Canonical trajectories

Trips that pass every validation stage are transformed into `core.trips`.

Each accepted record includes:

* source trip and taxi identifiers;
* call and origin metadata;
* reconstructed start time;
* trajectory point count;
* a PostGIS `LINESTRING` geometry using SRID 4326.

A GiST index supports downstream spatial queries. During full-table rebuilds, the spatial index can be created after bulk insertion to avoid unnecessary per-row index maintenance.

## Original road-network functionality

The original implementation extended the trajectory data with an OpenStreetMap road graph.

It included:

* conversion of OpenStreetMap data into routable road edges;
* pgRouting topology construction;
* nearest-edge map matching;
* percent-along-edge representations for matched observations;
* shortest-path cost calculations;
* service-station detour ranking;
* geometric trajectory comparison;
* DTW-inspired comparison over network travel costs;
* comparisons between indexing strategies and routing algorithms using `EXPLAIN ANALYZE`.

These components are being migrated into the refactored architecture rather than copied across unchanged.

## Quick start

### Prerequisites

* Docker Desktop or Docker Engine with Compose;
* Make;
* Python 3.13;
* `pyenv` or another Python environment manager.

### Configure the environment

```bash
cp .env.example .env
```

Review the database settings in `.env`, then start PostgreSQL:

```bash
make db-up
```

For a fresh database, initialise the database objects using the setup targets listed by:

```bash
make help
```

### Prepare the taxi dataset

The full dataset is not committed to the repository.

Prepare the source archives and extract `train.csv` with:

```bash
make prepare-taxi-data
```

The resulting file should be located at:

```text
data/raw/taxi/train.csv
```

### Run the complete taxi pipeline

```bash
make check-taxi-full
```

The full workflow:

1. runs the Python velocity tests;
2. loads all taxi records into PostgreSQL;
3. applies structural validation;
4. runs full-dataset velocity validation;
5. merges velocity rejections into PostgreSQL;
6. rebuilds canonical PostGIS trajectories;
7. runs SQL assertions;
8. prints rejection counts and row reconciliation.

For faster sample-based development:

```bash
make check-taxi-staging
make check-core-trips
```

View all supported commands with:

```bash
make help
```

## Testing

### Python tests

The Python suite covers:

* stationary trajectories;
* trajectories with too few points;
* known-distance velocity calculations;
* malformed coordinate arrays;
* threshold acceptance and rejection;
* maximum-speed segment identification;
* agreement between scalar and NumPy implementations;
* agreement on real trajectory samples.

Run:

```bash
make test-python
```

### SQL assertions

SQL assertions verify:

* staging-table invariants;
* rejection-record consistency;
* accepted and rejected row reconciliation;
* geometry type and SRID;
* valid trajectory point counts;
* valid canonical geometries.

Run the complete database workflow with:

```bash
make check-taxi-full
```

## Performance engineering

Performance analysis is a recurring theme of the project.

The work includes:

* Python microbenchmarks;
* algorithmic complexity analysis;
* vectorisation experiments;
* spatial indexing;
* routing-algorithm comparisons;
* `EXPLAIN ANALYZE`;
* PostgreSQL execution-plan inspection;
* bulk-load and index-maintenance considerations.

The objective is not merely to make queries faster, but to measure where runtime is spent and distinguish meaningful algorithmic improvements from smaller implementation-level effects.

## Repository structure

```text
.
├── data/
│   ├── raw/                  # Downloaded source data; not committed
│   └── interim/              # Generated samples and rejection outputs
├── docs/
│   └── velocity-validation.md
├── scripts/
│   ├── benchmark_velocity.py
│   └── velocity_experiments.py
├── sql/
│   ├── exploration/          # Profiling and inspection queries
│   └── pipeline/             # Ordered pipeline transformations
├── src/
│   └── road_trajectory_analysis/
├── tests/
│   ├── python/
│   └── sql/
├── compose.yaml
├── Makefile
└── pyproject.toml
```

## Roadmap

### Taxi trajectory pipeline

* [x] raw staging workflow;
* [x] structural validation;
* [x] velocity validation;
* [x] rejection diagnostics;
* [x] canonical PostGIS trajectories;
* [x] Python tests;
* [x] SQL assertions;
* [x] full-dataset orchestration;
* [x] finalise degenerate-geometry rejection handling;
* [x] merge refactor into `main`.

### Road-network layer

* [ ] migrate OpenStreetMap ingestion;
* [ ] normalise routable road edges;
* [ ] rebuild pgRouting topology;
* [ ] verify shortest-path behaviour.

### Analysis layer

* [ ] migrate GPS map matching;
* [ ] rebuild service-station detour analysis;
* [ ] rebuild network-aware trajectory comparison;
* [ ] compare geometric and network-aware similarity;
* [ ] repeat indexing and query-plan experiments within the refactored system.

## Data sources

* Porto taxi trajectory dataset from the ECML/PKDD 2015 taxi trajectory prediction challenge;
* OpenStreetMap road-network data.

Raw datasets and generated database state are excluded from version control.

## Background

This project began as a university assignment focused on geospatial SQL, pgRouting and query-performance analysis.

The current work is a substantial engineering refactor intended to make the system reproducible, inspectable and suitable as a public software-engineering portfolio project.
