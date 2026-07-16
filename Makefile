ifneq (,$(wildcard ./.env))
include .env
export
endif


TAXI_OUTER_ARCHIVE := $(TAXI_DATA_DIR)/taxi_dataset.zip
TAXI_INNER_ARCHIVE := $(TAXI_DATA_DIR)/train.csv.zip

TAXI_SAMPLE_PATH := data/interim/taxi_trips_sample.csv
TAXI_SAMPLE_SIZE := 1000

CORE_TRIP_SAMPLE_PATH := data/interim/core_trip_sample.geojson

VELOCITY_REJECTIONS_PATH := data/interim/velocity_rejections.csv
VELOCITY_REJECTIONS_FULL_PATH := data/interim/velocity_rejections_full.csv
VELOCITY_BENCHMARK_SIZE := 100000
VELOCITY_PROFILE_SIZE := 100000

PYTHON := .venv/bin/python
PYTEST := .venv/bin/pytest
PYTHON_ENV := PYTHONPATH=src:.


.PHONY: \
	help \
	db-up \
	db-down \
	db-status \
	db-shell \
	db-init \
	prepare-taxi-data \
	create-taxi-tables \
	create-taxi-sample \
	load-taxi-sample \
	validate-taxi-staging \
	test-taxi-staging \
	profile-taxi-staging \
	check-taxi-staging \
	build-core-trips \
	inspect-core-trips \
	test-core-trips \
	export-core-trip-sample \
	check-core-trips \
	test-python \
	test-velocity-validation \
	validate-taxi-velocity \
	benchmark-velocity \
	profile-velocity-sample \
	load-taxi-full \
	validate-taxi-velocity-full \
	merge-velocity-rejections \
	summarise-taxi-full \
	check-taxi-full


help:
	@echo "Available commands:"
	@echo ""
	@echo "Database:"
	@echo "  make db-up                         Start the database"
	@echo "  make db-down                       Stop the database"
	@echo "  make db-status                     Show database container status"
	@echo "  make db-shell                      Open a PostgreSQL shell"
	@echo "  make db-init                       Create extensions and schemas"
	@echo ""
	@echo "Taxi staging:"
	@echo "  make prepare-taxi-data             Download and extract the taxi dataset"
	@echo "  make create-taxi-tables            Create taxi staging tables"
	@echo "  make create-taxi-sample            Create a local sample CSV"
	@echo "  make load-taxi-sample              Load the sample into staging"
	@echo "  make validate-taxi-staging         Populate SQL rejection records"
	@echo "  make test-taxi-staging             Run staging assertions"
	@echo "  make profile-taxi-staging          Print staging data profile"
	@echo "  make check-taxi-staging            Run the full sample staging workflow"
	@echo ""
	@echo "Core trips:"
	@echo "  make build-core-trips              Build canonical PostGIS trajectories"
	@echo "  make inspect-core-trips            Print a sample of canonical trips"
	@echo "  make test-core-trips               Run canonical trip assertions"
	@echo "  make export-core-trip-sample       Export sample trajectories as GeoJSON"
	@echo "  make check-core-trips              Run the full canonical-trip workflow"
	@echo ""
	@echo "Velocity validation:"
	@echo "  make test-python                   Run all Python tests"
	@echo "  make test-velocity-validation      Run velocity and equivalence tests"
	@echo "  make validate-taxi-velocity        Generate sample velocity rejections"
	@echo "  make benchmark-velocity            Benchmark velocity implementations"
	@echo "  make profile-velocity-sample       Profile maximum-speed distributions"
	@echo ""
	@echo "Full Taxi Data Ingestion"
	@echo "  make load-taxi-full                Load the full taxi dataset into staging"
	@echo "  make validate-taxi-velocity-full   Generate full velocity rejections"
	@echo "  make merge-velocity-rejections     Merge velocity results into PostgreSQL"
	@echo "  make summarise-taxi-full           Print full-pipeline counts and statistics"
	@echo "  make check-taxi-full               Run the complete full-data taxi pipeline"

db-up:
	docker compose up -d


db-down:
	docker compose down


db-status:
	docker compose ps


db-shell:
	docker compose exec db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB)


db-init:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/pipeline/001_initialise_database.sql


setup-database:
	$(MAKE) db-up
	$(MAKE) db-init
	$(MAKE) create-taxi-tables
	@echo "Database schema initialised successfully."

	
prepare-taxi-data:
	mkdir -p $(TAXI_DATA_DIR)
	curl \
		--fail \
		--location \
		--continue-at - \
		--output $(TAXI_OUTER_ARCHIVE) \
		"$(TAXI_DATA_URL)"
	unzip -o \
		$(TAXI_OUTER_ARCHIVE) \
		train.csv.zip \
		-d $(TAXI_DATA_DIR)
	unzip -o \
		$(TAXI_INNER_ARCHIVE) \
		-d $(TAXI_DATA_DIR)
	rm -f \
		$(TAXI_OUTER_ARCHIVE) \
		$(TAXI_INNER_ARCHIVE)
	@test -f "$(TAXI_DATA_PATH)" || { \
		echo "Expected dataset not found at $(TAXI_DATA_PATH)"; \
		exit 1; \
	}
	@echo "Taxi dataset ready at $(TAXI_DATA_PATH)"
	@du -h $(TAXI_DATA_PATH)
	@wc -l $(TAXI_DATA_PATH)
	@head -n 1 $(TAXI_DATA_PATH)


create-taxi-tables:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/pipeline/002_create_taxi_tables.sql


create-taxi-sample:
	mkdir -p data/interim
	head -n $$(( $(TAXI_SAMPLE_SIZE) + 1 )) $(TAXI_DATA_PATH) \
		> $(TAXI_SAMPLE_PATH)
	@test "$$(wc -l < $(TAXI_SAMPLE_PATH) | tr -d ' ')" \
		-eq "$$(( $(TAXI_SAMPLE_SIZE) + 1 ))"
	@echo "Created $(TAXI_SAMPLE_SIZE)-row sample at $(TAXI_SAMPLE_PATH)"


load-taxi-sample: create-taxi-sample
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "TRUNCATE TABLE staging.trip_rejections, staging.taxi_trips_raw RESTART IDENTITY;"

	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "\copy staging.taxi_trips_raw (trip_id, call_type, origin_call, origin_stand, taxi_id, source_timestamp, day_type, missing_data, polyline_raw) FROM STDIN WITH (FORMAT csv, HEADER true, NULL '', FORCE_NULL (origin_call, origin_stand));" \
		< $(TAXI_SAMPLE_PATH)

	@echo "Loaded sample rows:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-tAc "SELECT count(*) FROM staging.taxi_trips_raw;"


validate-taxi-staging:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/pipeline/003_validate_taxi_staging.sql

	@echo "Taxi validation summary:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "SELECT reason, count(*) AS rejected_rows FROM staging.trip_rejections GROUP BY reason ORDER BY reason;"


test-taxi-staging:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< tests/sql/taxi_staging_assertions.sql
	@echo "Taxi staging tests passed."


profile-taxi-staging:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/exploration/taxi_staging_profile.sql


check-taxi-staging:
	$(MAKE) load-taxi-sample
	$(MAKE) validate-taxi-staging
	$(MAKE) test-taxi-staging
	$(MAKE) profile-taxi-staging
	@echo "Taxi staging workflow completed successfully."


build-core-trips:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/pipeline/004_build_core_trips.sql

	@echo "Core trip summary:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "SELECT count(*) AS accepted_trips, min(point_count) AS minimum_points, round(avg(point_count), 2) AS average_points, max(point_count) AS maximum_points FROM core.trips;"


inspect-core-trips:
	docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "SELECT trip_id, taxi_id, started_at, point_count, ST_GeometryType(geom) AS geometry_type, ST_AsText(ST_StartPoint(geom)) AS start_point, ST_AsText(ST_EndPoint(geom)) AS end_point FROM core.trips ORDER BY started_at LIMIT 10;"


test-core-trips:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< tests/sql/core_trips_assertions.sql
	@echo "Core trip tests passed."


export-core-trip-sample:
	mkdir -p data/interim
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/exploration/export_core_trip_sample.sql \
		> $(CORE_TRIP_SAMPLE_PATH)
	@$(PYTHON) -m json.tool $(CORE_TRIP_SAMPLE_PATH) > /dev/null
	@echo "Exported $(CORE_TRIP_SAMPLE_PATH)"
	@echo "Open this file in a GeoJSON viewer to inspect the trajectories."


check-core-trips:
	$(MAKE) check-taxi-staging
	$(MAKE) build-core-trips
	$(MAKE) test-core-trips
	$(MAKE) inspect-core-trips
	$(MAKE) export-core-trip-sample
	@echo "Canonical trip workflow completed successfully."


test-python:
	$(PYTHON_ENV) $(PYTEST) tests/python -v


test-velocity-validation:
	$(PYTHON_ENV) $(PYTEST) \
		tests/python/test_velocity_validation.py \
		tests/python/test_velocity_experiments.py \
		-v


validate-taxi-velocity:
	$(PYTHON_ENV) $(PYTHON) \
		-m road_trajectory_analysis.validate_velocity \
		--input $(TAXI_SAMPLE_PATH) \
		--output $(VELOCITY_REJECTIONS_PATH)


benchmark-velocity:
	$(PYTHON_ENV) $(PYTHON) \
		scripts/benchmark_velocity.py \
		--input $(TAXI_DATA_PATH) \
		--limit $(VELOCITY_BENCHMARK_SIZE) \
		--repeats 5


profile-velocity-sample:
	$(PYTHON_ENV) $(PYTHON) \
		-m road_trajectory_analysis.profile_velocity \
		--input $(TAXI_DATA_PATH) \
		--limit $(VELOCITY_PROFILE_SIZE)


load-taxi-full:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "TRUNCATE TABLE staging.trip_rejections, staging.taxi_trips_raw RESTART IDENTITY;"

	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "\copy staging.taxi_trips_raw (trip_id, call_type, origin_call, origin_stand, taxi_id, source_timestamp, day_type, missing_data, polyline_raw) FROM STDIN WITH (FORMAT csv, HEADER true, NULL '', FORCE_NULL (origin_call, origin_stand));" \
		< $(TAXI_DATA_PATH)

	@expected=$$(($$(wc -l < $(TAXI_DATA_PATH)) - 1)); \
	actual=$$(docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-tAc "SELECT count(*) FROM staging.taxi_trips_raw;" \
		| tr -d '[:space:]'); \
	if [ "$$actual" -ne "$$expected" ]; then \
		echo "Full load failed: expected $$expected rows, found $$actual"; \
		exit 1; \
	fi; \
	echo "Loaded and verified $$actual taxi rows."


validate-taxi-velocity-full:
	$(PYTHON_ENV) $(PYTHON) \
		-m road_trajectory_analysis.validate_velocity \
		--input $(TAXI_DATA_PATH) \
		--output $(VELOCITY_REJECTIONS_FULL_PATH)

	@echo "Generated full velocity rejection file:"
	@wc -l $(VELOCITY_REJECTIONS_FULL_PATH)


merge-velocity-rejections:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "DROP TABLE IF EXISTS staging.velocity_rejections_raw; CREATE UNLOGGED TABLE staging.velocity_rejections_raw (trip_id bigint NOT NULL, max_speed_kmh double precision NOT NULL, segment_index integer NOT NULL);"

	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "\copy staging.velocity_rejections_raw (trip_id, max_speed_kmh, segment_index) FROM STDIN WITH (FORMAT csv, HEADER true);" \
		< $(VELOCITY_REJECTIONS_FULL_PATH)

	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/pipeline/005_merge_velocity_rejections.sql

	@echo "Merged velocity rejections:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-tAc "SELECT count(*) FROM staging.trip_rejections WHERE reason = 'implausible_velocity';"


summarise-taxi-full:
	@echo "Rejection summary:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "SELECT reason, count(*) AS rejection_records, count(DISTINCT ingestion_id) AS rejected_rows FROM staging.trip_rejections GROUP BY reason ORDER BY reason;"

	@echo "Pipeline row reconciliation:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "SELECT (SELECT count(*) FROM staging.taxi_trips_raw) AS staged_rows, (SELECT count(DISTINCT ingestion_id) FROM staging.trip_rejections) AS rejected_rows, (SELECT count(*) FROM core.trips) AS accepted_core_trips;"

	@echo "Core trip profile:"
	@docker compose exec -T db \
		psql \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		-c "SELECT min(point_count) AS minimum_points, round(avg(point_count), 2) AS average_points, percentile_cont(0.5) WITHIN GROUP (ORDER BY point_count) AS median_points, max(point_count) AS maximum_points, ST_Extent(geom) AS spatial_extent FROM core.trips;"


check-taxi-full:
	$(MAKE) test-velocity-validation
	$(MAKE) load-taxi-full
	$(MAKE) validate-taxi-staging
	$(MAKE) validate-taxi-velocity-full
	$(MAKE) merge-velocity-rejections
	$(MAKE) build-core-trips
	$(MAKE) test-core-trips
	$(MAKE) summarise-taxi-full
	@echo "Full taxi ingestion and validation pipeline completed successfully."