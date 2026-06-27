ifneq (,$(wildcard ./.env))
include .env
export
endif

TAXI_OUTER_ARCHIVE := $(TAXI_DATA_DIR)/taxi_dataset.zip
TAXI_INNER_ARCHIVE := $(TAXI_DATA_DIR)/train.csv.zip

.PHONY: db-up db-down db-status db-shell db-init prepare-taxi-data load-taxi-sample

db-up:
	docker compose up -d

db-down:
	docker compose down

db-status:
	docker compose ps

db-shell:
	docker compose exec db \
		psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

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

TAXI_SAMPLE_PATH := data/interim/taxi_trips_sample.csv
TAXI_SAMPLE_SIZE := 1000

.PHONY: create-taxi-sample

create-taxi-sample:
	mkdir -p data/interim
	head -n $$(( $(TAXI_SAMPLE_SIZE) + 1 )) $(TAXI_DATA_PATH) \
		> $(TAXI_SAMPLE_PATH)
	@test "$$(wc -l < $(TAXI_SAMPLE_PATH) | tr -d ' ')" \
		-eq "$$(( $(TAXI_SAMPLE_SIZE) + 1 ))"
	@echo "Created $(TAXI_SAMPLE_SIZE)-row sample at $(TAXI_SAMPLE_PATH)"

.PHONY: load-taxi-sample

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

.PHONY: profile-taxi-staging

profile-taxi-staging:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< sql/exploration/taxi_staging_profile.sql

.PHONY: test-taxi-staging

test-taxi-staging:
	docker compose exec -T db \
		psql \
		-v ON_ERROR_STOP=1 \
		-U $(POSTGRES_USER) \
		-d $(POSTGRES_DB) \
		< tests/sql/taxi_staging_assertions.sql
	@echo "Taxi staging tests passed."

.PHONY: check-taxi-staging

check-taxi-staging: load-taxi-sample test-taxi-staging profile-taxi-staging