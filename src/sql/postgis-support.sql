CREATE OR REPLACE FUNCTION zdb.enable_postgis_support() RETURNS boolean VOLATILE LANGUAGE plpgsql AS $func$
DECLARE
  postgis_installed boolean := (SELECT count(*) > 0 FROM pg_extension WHERE extname = 'postgis');
  geojson_namespace text := (SELECT (SELECT nspname FROM pg_namespace WHERE oid = pronamespace) FROM pg_proc WHERE proname = 'st_asgeojson' limit 1);
BEGIN

  IF postgis_installed THEN
    -- casting functions
    EXECUTE format('create or replace function zdb.geometry_to_json(%I.geometry) returns json parallel safe immutable strict language sql as ''select %I.st_asgeojson($1)::json;''; ', geojson_namespace, geojson_namespace);
    EXECUTE format('create or replace function zdb.geography_to_json(%I.geography) returns json parallel safe immutable strict language sql as ''select %I.st_asgeojson($1)::json;''; ', geojson_namespace, geojson_namespace);

    -- casts
    EXECUTE format('CREATE CAST (%I.geometry AS json) WITH FUNCTION zdb.geometry_to_json;', geojson_namespace);
    EXECUTE format('CREATE CAST (%I.geography AS json) WITH FUNCTION zdb.geography_to_json;', geojson_namespace);

    -- zdb type mappings
    EXECUTE format($$ SELECT zdb.define_type_mapping('%I.geometry'::regtype,  '{"type":"geo_shape"}'); $$, geojson_namespace);
    EXECUTE format($$ SELECT zdb.define_type_mapping('%I.geography'::regtype, '{"type":"geo_shape"}'); $$, geojson_namespace);

  END IF;

  RETURN postgis_installed;
END;
$func$;

/*
"geo_shape": {
    "location": {
        "shape": {
            "type": "envelope",
            "coordinates" : [[13.0, 53.0], [14.0, 52.0]]
        },
        "relation": "within"
    }
}
*/
CREATE TYPE dsl.es_geo_shape_relation AS ENUM ('INTERSECTS', 'DISJOINT', 'WITHIN', 'CONTAINS');
CREATE OR REPLACE FUNCTION dsl.geo_shape(field text, geojson_shape json, relation dsl.es_geo_shape_relation) RETURNS zdbquery PARALLEL SAFE IMMUTABLE STRICT LANGUAGE sql AS $$
  SELECT json_build_object('geo_shape', json_build_object(field, json_build_object('shape', geojson_shape, 'relation', relation)))::zdbquery;
$$;