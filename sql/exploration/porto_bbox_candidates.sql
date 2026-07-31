\echo 'Full accepted trajectory extent'
SELECT ST_Extent(geom) AS full_extent
FROM core.trips;

\echo 'Robust accepted trajectory point extent'
WITH trip_points AS (
    SELECT dumped.geom AS geom
    FROM core.trips
    CROSS JOIN LATERAL ST_DumpPoints(core.trips.geom) AS dumped
)
SELECT
    percentile_cont(0.001) WITHIN GROUP (ORDER BY ST_X(geom)) AS lon_p001,
    percentile_cont(0.999) WITHIN GROUP (ORDER BY ST_X(geom)) AS lon_p999,
    percentile_cont(0.001) WITHIN GROUP (ORDER BY ST_Y(geom)) AS lat_p001,
    percentile_cont(0.999) WITHIN GROUP (ORDER BY ST_Y(geom)) AS lat_p999
FROM trip_points;

\echo 'Robust start/end point extent'
WITH endpoints AS (
    SELECT ST_StartPoint(geom) AS geom FROM core.trips
    UNION ALL
    SELECT ST_EndPoint(geom) AS geom FROM core.trips
)
SELECT
    percentile_cont(0.001) WITHIN GROUP (ORDER BY ST_X(geom)) AS lon_p001,
    percentile_cont(0.999) WITHIN GROUP (ORDER BY ST_X(geom)) AS lon_p999,
    percentile_cont(0.001) WITHIN GROUP (ORDER BY ST_Y(geom)) AS lat_p001,
    percentile_cont(0.999) WITHIN GROUP (ORDER BY ST_Y(geom)) AS lat_p999
FROM endpoints;