#!/usr/bin/env bash
# 연습 프로젝트를 초기 상태로 되돌린다 (DuckDB 파일 + 빌드 산출물 삭제, 시드 CSV 복원).
set -euo pipefail
cd "$(dirname "$0")"

rm -f dev.duckdb dev.duckdb.wal
rm -rf target logs

printf 'user_id,plan_tier,updated_at\nu1,free,2026-01-01 00:00:00\nu2,pro,2026-01-05 00:00:00\nu3,free,2026-01-10 00:00:00\n' > seeds/users_raw.csv
printf 'event_id,user_id,event_type,event_at\ne1,u1,open,2026-05-01 09:00:00\ne2,u2,edit,2026-05-01 10:00:00\ne3,u1,export,2026-05-02 11:00:00\ne4,u3,open,2026-05-02 12:00:00\n' > seeds/events_raw.csv

echo "초기화 완료. README_연습가이드.md 의 실습 A-1 부터 시작하세요."
