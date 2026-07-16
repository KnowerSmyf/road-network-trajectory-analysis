# Road-Network Trajectory Analysis

A geospatial data pipeline for validating, transforming, and comparing GPS trajectories using the underlying road network rather than straight-line distance.

The project uses the Porto taxi trajectory dataset as its primary data source. Raw taxi trips are ingested into PostgreSQL, validated for structural and physical plausibility, converted into canonical PostGIS geometries, and prepared for later map matching and network-aware trajectory comparison.

> **Development status:** The taxi ingestion and validation pipeline has been rebuilt on the `refactor/taxi-ingestion` branch. Road-network ingestion, map matching, and trajectory similarity are the next stages of the refactor.

## Why network-aware trajectory analysis?

Two trajectories can appear close under ordinary Euclidean distance while following different roads, crossing barriers, or travelling in opposite directions around the same street network.

This project instead represents trajectory similarity in terms of movement through a road graph:

1. validate and normalise raw GPS trajectories;
2. map observations onto OpenStreetMap road edges;
3. measure travel distance through the road network with pgRouting;
4. compare ordered trajectories using a DTW-inspired similarity calculation.

The current refactor focuses on making the data pipeline reproducible, testable, and suitable for processing the complete Porto taxi dataset.

## Current pipeline

The implemented pipeline processes approximately 1.7 million taxi trips:

```text
Porto taxi CSV
    ↓
staging.taxi_trips_raw
    ↓
structural validation
    ↓
velocity validation
    ↓
staging.trip_rejections
    ↓
core.trips
```

### Raw ingestion

The source CSV is loaded into a staging schema without prematurely transforming or discarding source values.

Each staged row receives an internal ingestion identifier, allowing validation failures to be recorded independently of the source trip identifier.

### Structural validation

SQL validation records rejected rows and their reasons in `staging.trip_rejections`.

Current checks include:

* source rows marked as containing missing data;
* missing required values;
* invalid categorical values;
* trajectories with insufficient coordinates;
* duplicate trip identifiers.

Validation is non-destructive: rejected rows remain available in staging for inspection and debugging.

### Velocity validation

A Python validator examines the implied speed between consecutive GPS observations, which are sampled at 15-second intervals.

Trips are rejected when any segment implies a speed greater than 200 km/h. This is intended to identify severe GPS jumps and corrupted trajectories rather than enforce ordinary road speed limits.

The original university implementation constructed a full pairwise distance matrix for each trajectory, despite requiring only consecutive distances. The refactored implementation reduces the calculation from (O(n^2)) to (O(n)) per trip and uses NumPy for the production calculation.

On the complete dataset, the revised validator processes all trajectories in roughly 40 seconds on the development machine.

Further details are available in [`docs/velocity-validation.md`](docs/velocity-validation.md).

### Canonical trajectories

Rows that pass every validation stage are transformed into `core.trips`.

Each accepted trip contains:

* source trip and taxi identifiers;
* call and origin metadata;
* reconstructed start time;
* trajectory point count;
* a PostGIS `LINESTRING` geometry using SRID 4326.

The canonical table provides a clean input for downstream spatial processing without repeatedly parsing the original JSON polylines.

## Reproducible workflow

The pipeline is orchestrated through `make`.

Run the complete taxi pipeline with:

```bash
make check-taxi-full
```

This command:

1. runs the Python velocity tests;
2. loads the complete taxi dataset into PostgreSQL;
3. applies structural validation;
4. generates full-dataset velocity rejections;
5. merges validation results into PostgreSQL;
6. rebuilds the canonical trip table;
7. executes SQL assertions;
8. reports rejection counts and final pipeline statistics.

For faster development, sample-based targets are also available:

```bash
make check-taxi-staging
make check-core-trips
```

View all available commands with:

```bash
make help
```

## Testing

The project includes both Python and SQL tests.

Python tests cover:

* stationary and insufficient-point trajectories;
* known-distance velocity calculations;
* invalid coordinate shapes;
* threshold acceptance and rejection;
* maximum-speed segment identification;
* agreement between scalar reference implementations and NumPy;
* agreement on a real trajectory sample.

SQL assertions verify:

* staging-table invariants;
* rejection consistency;
* canonical trip geometry types and SRIDs;
* valid trajectory point counts;
* reconciliation between staged, rejected, and accepted rows.

Run the Python suite with:

```bash
make test-python
```

## Project structure

```text
.
├── data/
│   ├── raw/                  # Downloaded source data, not committed
│   └── interim/              # Generated samples and rejection files
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

## Technologies

* Python
* NumPy
* PostgreSQL
* PostGIS
* pgRouting
* SQL
* Docker Compose
* pytest
* OpenStreetMap
* Overpass API
* GDAL / ogr2ogr

## Dataset

The project uses the Porto taxi trajectory dataset from the ECML/PKDD 2015 taxi trajectory prediction challenge.

The full dataset is not committed to this repository. It is downloaded and prepared locally through the project workflow:

```bash
make prepare-taxi-data
```

The preparation step downloads and extracts the source archives, producing:

```text
data/raw/taxi/train.csv
```

Raw and generated data files are excluded from version control.

## Roadmap

The current refactor is organised into four stages.

### 1. Taxi ingestion and validation

* [x] reproducible PostgreSQL staging workflow;
* [x] structural data-quality validation;
* [x] linear-time velocity validation;
* [x] persistent rejection records with diagnostic details;
* [x] canonical PostGIS trip geometries;
* [x] Python and SQL assertions;
* [x] full-dataset Make orchestration.

### 2. Canonical trajectory points

* [ ] expand accepted trips into ordered observations;
* [ ] reconstruct per-point timestamps;
* [ ] add point-level spatial indexes and assertions.

### 3. Road-network processing

* [ ] ingest the Porto road network from OpenStreetMap;
* [ ] normalise routable road edges;
* [ ] create pgRouting topology;
* [ ] validate shortest-path queries.

### 4. Map matching and trajectory similarity

* [ ] map GPS observations to nearby road edges;
* [ ] represent matched positions using edge identifiers and fractional positions;
* [ ] calculate road-network distance between observations;
* [ ] implement DTW-inspired trajectory similarity;
* [ ] evaluate and visualise example trajectory comparisons.

## Background

This project began as a university assignment exploring road-network trajectory similarity with PostGIS and pgRouting.

The current version is a substantial engineering refactor of that work. The objective is not merely to preserve the original result, but to turn it into a reproducible and inspectable geospatial system with explicit schemas, validation stages, automated tests, performance benchmarks, and documented design decisions.
