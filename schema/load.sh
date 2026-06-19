#!/usr/bin/env bash
# ============================================================================
# Carga el flujo de eventos sintético (WS-A) a PostgreSQL.
#   1. Aplica las migraciones (001 core, 002 vistas).
#   2. \copy de los CSV generados por el simulador (out/wsa/*.csv).
#
# Uso:
#   DB=maintenance ./schema/load.sh                 # usa la DB 'maintenance' (la crea si falta)
#   DB=maintenance CSVDIR=out/wsa ./schema/load.sh
#
# Requiere: psql en PATH. TimescaleDB es opcional (la migración la detecta).
# ============================================================================
set -euo pipefail

DB="${DB:-maintenance}"
CSVDIR="${CSVDIR:-out/wsa}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CSV="$ROOT/$CSVDIR"

if [ ! -f "$CSV/vehicle.csv" ]; then
  echo "No encuentro $CSV/vehicle.csv — corre primero:  julia run_simulation.jl" >&2
  exit 1
fi

echo ">> Creando base de datos '$DB' (si no existe)…"
createdb "$DB" 2>/dev/null || true

echo ">> Aplicando migraciones…"
psql -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/schema/migrations/001_wsa_core.sql"
psql -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/schema/migrations/002_survival_view.sql"

echo ">> Cargando CSV (orden respeta las llaves foráneas)…"
psql -d "$DB" -v ON_ERROR_STOP=1 <<SQL
\copy vehicle (vehicle_id,class,brand,model,model_year,gvwr_kg,diagnostic_protocol,onboarded_at,route_severity,hours_per_day) FROM '$CSV/vehicle.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy position (position_id,vehicle_id,component_type,location) FROM '$CSV/position.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy component_instance (instance_id,position_id,part_number,supplier,install_time,install_known,install_engine_h,removal_time) FROM '$CSV/component_instance.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy event (event_id,instance_id,type,event_time,onset_lower,onset_upper,engine_h,odo_km,mode_id,restoration_q,cost_parts,cost_labor,cost_towing,downtime_h,in_route,cost_fine,source,dtc_spn,dtc_fmi) FROM '$CSV/event.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy usage_snapshot (vehicle_id,ts,engine_h,odo_km,brake_energy_cum,rainflow_miner_cum,route_severity) FROM '$CSV/usage_snapshot.csv' WITH (FORMAT csv, HEADER true, NULL '')
SQL

echo ">> Verificación rápida:"
psql -d "$DB" -c "SELECT
  (SELECT count(*) FROM vehicle)            AS vehiculos,
  (SELECT count(*) FROM component_instance) AS instancias,
  (SELECT count(*) FROM event)              AS eventos,
  (SELECT count(*) FROM event WHERE type='failure')  AS fallas,
  (SELECT count(*) FROM event WHERE type='auto_dtc') AS dtcs,
  (SELECT count(*) FROM surv_engineh WHERE status=0) AS censurados;"

echo ">> Listo. Vista de supervivencia: SELECT * FROM surv_engineh LIMIT 10;"
echo ">> Órdenes CBM:                   SELECT * FROM cbm_work_orders LIMIT 10;"
