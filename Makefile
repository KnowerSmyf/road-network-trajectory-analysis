ifneq (,$(wildcard ./.env))
include .env
export
endif

TAXI_OUTER_ARCHIVE := $(TAXI_DATA_DIR)/taxi_dataset.zip
TAXI_INNER_ARCHIVE := $(TAXI_DATA_DIR)/train.csv.zip
TAXI_SAMPLE_PATH := data/interim/taxi_trips_sample.csv
TAXI_SAMPLE_SIZE := 1000

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
	check-taxi-staging

help:
	@echo "Available commands:"
	@echo "  make db-up                  Start the database"
	@echo "  make db-down                Stop the database"
	@echo "  make db-status              Show database container status"
	@echo "  make db-shell               Open a PostgreSQL shell"
	@echo "  make db-init                Create extensions and schemas"
	@echo "  make prepare-taxi-data      Download and extract the taxi dataset"
	@echo "  make create-taxi-tables     Create taxi staging tables"
	@echo "  make create-taxi-sample     Create a local sample CSV"
	@echo "  make load-taxi-sample       Load the sample into staging"
	@echo "  make validate-taxi-staging  Populate trip rejection records"
	@echo "  make test-taxi-staging      Run staging assertions"
	@echo "  make profile-taxi-staging   Print staging data profile"
	@echo "  make check-taxi-staging     Run the full sample staging workflow"

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

check-taxi-staging: \
	create-taxi-tables \
	load-taxi-sample \
	validate-taxi-staging \
	test-taxi-staging \
	profile-taxi-staging
	@echo "Taxi staging workflow completed successfully."
