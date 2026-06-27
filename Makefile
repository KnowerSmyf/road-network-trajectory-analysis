ifneq (,$(wildcard ./.env))
include .env
export
endif

TAXI_OUTER_ARCHIVE := $(TAXI_DATA_DIR)/taxi_dataset.zip
TAXI_INNER_ARCHIVE := $(TAXI_DATA_DIR)/train.csv.zip

.PHONY: db-up db-down db-status db-shell db-init prepare-taxi-data

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