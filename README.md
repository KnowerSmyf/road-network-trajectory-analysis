# Road-Network Trajectory Analysis

This project explores network-aware similarity between GPS trajectories by mapping raw GPS points onto an OpenStreetMap road network and comparing routes using road travel distances rather than naive Euclidean distances.

## Overview

The system uses PostgreSQL/PostGIS for spatial storage and querying, PgRouting for shortest-path calculations over the road graph, and SQL/Python workflows for processing trajectory data.

## Key Features

- Ingested and processed road network data from OpenStreetMap.
- Mapped GPS points to nearest road edges using spatial queries.
- Represented matched points using edge identifiers and percent-along-edge positions.
- Computed road-network travel distances using PgRouting shortest paths.
- Developed DTW-inspired trajectory similarity logic over ordered GPS point sequences.

## Technologies

- PostgreSQL
- PostGIS
- PgRouting
- SQL
- Python
- OpenStreetMap / Overpass Turbo

## Status

This repository is being cleaned and prepared for public release. Initial documentation and selected implementation files will be added progressively.