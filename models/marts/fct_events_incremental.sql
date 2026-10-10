-- ============================================================================
-- 갭 #4 — Incremental model + late-arriving data 실습
-- ============================================================================
-- materialized='incremental' : 매번 전체 재빌드하지 않고 신규/변경분만 추가.
-- unique_key='event_id'      : 중복 방지 키.
-- incremental_strategy='delete+insert' :
--     배치에 들어온 event_id를 target에서 먼저 삭제 후 재삽입 → 재처리해도 중복 없음.
--     (Redshift도 과거 merge 미지원 시절 이 전략을 많이 썼다 → 알아둘 포인트.)
--
-- on_schema_change='append_new_columns' : upstream에 컬럼이 추가돼도 빌드가 깨지지 않게.
-- ============================================================================
{{
    config(
        materialized='incremental',
        unique_key='event_id',
        incremental_strategy='delete+insert',
        on_schema_change='append_new_columns'
    )
}}

with src as (
    select
        event_id,
        user_id,
        event_type,
        cast(event_at as timestamp) as event_at
    from {{ ref('events_raw') }}
)

select * from src

{% if is_incremental() %}
-- ── 증분 필터 (모델이 이미 존재하고 --full-refresh가 아닐 때만 적용) ──
-- 순진한 버전:  where event_at > (select max(event_at) from {{ this }})
--   → 늦게 도착한 과거 데이터(late-arriving)를 영원히 놓친다.
-- 방어:  lookback window(3일)를 둬서 max 근처 과거를 재처리.
--        delete+insert + unique_key 덕분에 재처리해도 중복이 안 생긴다.
where event_at > (select max(event_at) - interval '3 days' from {{ this }})
{% endif %}
