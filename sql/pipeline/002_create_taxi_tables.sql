CREATE TABLE staging.taxi_trips_raw (
    ingestion_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id bigint,
    call_type text,
    origin_call bigint,
    origin_stand integer,
    taxi_id integer,
    source_timestamp bigint,
    day_type text,
    missing_data boolean,
    polyline_raw text,
    ingested_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE staging.trip_rejections (
    rejection_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingestion_id bigint NOT NULL
        REFERENCES staging.taxi_trips_raw(ingestion_id)
        ON DELETE CASCADE,
    trip_id bigint,
    reason text NOT NULL,
    details jsonb,
    rejected_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (ingestion_id, reason)
);