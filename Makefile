ifneq (,$(wildcard ./.env))
include .env
export
endif

.PHONY: db-up db-down db-status db-shell db-init

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
