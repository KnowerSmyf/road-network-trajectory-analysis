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
	profile-velocity-sample


help:
	@echo "Available commands:"
	@echo ""
	@echo "Database:"
	@echo "  make db-up                     Start the database"
	@echo "  make db-down                   Stop the database"
	@echo "  make db-status                 Show database container status"
	@echo "  make db-shell                  Open a PostgreSQL shell"
	@echo "  make db-init                   Create extensions and schemas"
	@echo ""
	@echo "Taxi staging:"
	@echo "  make prepare-taxi-data         Download and extract the taxi dataset"
	@echo "  make create-taxi-tables        Create taxi staging tables"
	@echo "  make create-taxi-sample        Create a local sample CSV"
	@echo "  make load-taxi-sample          Load the sample into staging"
	@echo "  make validate-taxi-staging     Populate SQL rejection records"
	@echo "  make test-taxi-staging         Run staging assertions"
	@echo "  make profile-taxi-staging      Print staging data profile"
	@echo "  make check-taxi-staging        Run the full sample staging workflow"
	@echo ""
	@echo "Core trips:"
	@echo "  make build-core-trips          Build canonical PostGIS trajectories"
	@echo "  make inspect-core-trips        Print a sample of canonical trips"
	@echo "  make test-core-trips           Run canonical trip assertions"
	@echo "  make export-core-trip-sample   Export sample trajectories as GeoJSON"
	@echo "  make check-core-trips          Run the full canonical-trip workflow"
	@echo ""
	@echo "Velocity validation:"
	@echo "  make test-python               Run all Python tests"
	@echo "  make test-velocity-validation  Run velocity and equivalence tests"
	@echo "  make validate-taxi-velocity    Generate sample velocity rejections"
	@echo "  make benchmark-velocity        Benchmark velocity implementations"
	@echo "  make profile-velocity-sample   Profile maximum-speed distributions"


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
	$(MAKE) create-taxi-tables
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
