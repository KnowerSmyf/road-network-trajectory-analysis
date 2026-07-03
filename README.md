# Road-Network Trajectory Analysis

A geospatial transport-analysis system built over **1.7 million Porto taxi trips** and an **OpenStreetMap road network** using Python, PostgreSQL, PostGIS and pgRouting.

The project explores how GPS journeys can be validated, map-matched and compared using the roads they actually travel along rather than relying only on straight-line geometric distance.

> **Active development:** The ingestion and validation pipeline is currently being rebuilt on [`refactor/taxi-ingestion`](../../tree/refactor/taxi-ingestion). That branch contains the latest Docker, SQL, Python, testing and orchestration work.

## Project capabilities

The original implementation included:

* ingestion of Porto taxi trajectories and OpenStreetMap road data;
* construction of a routable pgRouting road graph;
* map matching of GPS observations to road segments;
* shortest-path routing over the road network;
* service-station detour analysis based on added network travel cost;
* geometric and DTW-inspired trajectory-similarity queries;
* query-plan, index and routing-algorithm experiments using `EXPLAIN ANALYZE`.

## Current refactor

The current refactor is converting the original coursework implementation into a reproducible and testable software project.

Completed or substantially implemented on `refactor/taxi-ingestion`:

* Docker-based PostgreSQL/PostGIS environment;
* reproducible ingestion of all 1,710,670 taxi records;
* separate staging, rejection and canonical data models;
* structural and physical-plausibility validation;
* explicit rejection diagnostics;
* canonical PostGIS `LINESTRING` trajectories;
* Python and SQL assertions;
* Make-based pipeline orchestration;
* controlled performance benchmarks.

The road-network ingestion, map-matching and analytical query layers will be migrated after the trajectory pipeline is finalised.

## System direction

```text
Raw taxi trajectories
        |
        v
Staging and validation
        |
        +----> Rejection diagnostics
        |
        v
Canonical PostGIS trajectories
        |
        v
OpenStreetMap road graph
        |
        v
Map matching and shortest paths
        |
        v
Network-aware trajectory analysis
```

## Performance work

The original velocity validator calculated a complete pairwise distance matrix for every trajectory, even though only consecutive observations were required.

The refactored implementation processes consecutive GPS observations directly, reducing the full-dataset validation run from approximately **30 minutes to 40 seconds** on the development machine.

Additional experiments compare:

* helper-function and inlined scalar calculations;
* native Python and NumPy implementations;
* spatial index strategies;
* routing algorithms;
* PostgreSQL execution plans.

## Technology

* Python
* NumPy
* PostgreSQL
* PostGIS
* pgRouting
* SQL
* Docker Compose
* pytest
* OpenStreetMap
* GDAL / ogr2ogr

## Development status

This repository began as a university geospatial-database project and is now being substantially refactored for public release.

For the latest implementation and setup instructions, see the [`refactor/taxi-ingestion`](../../tree/refactor/taxi-ingestion) branch.
