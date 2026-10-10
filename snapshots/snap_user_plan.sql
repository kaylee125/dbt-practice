-- ============================================================================
-- 갭 #1 — SCD Type 2 / dbt snapshot 실습
-- ============================================================================
-- dbt가 매 실행마다 source(여기선 users_raw)를 스캔해 "변경"을 감지하고,
-- 변경될 때마다 새 row + 유효구간 컬럼을 자동으로 관리한다.
--
-- dbt가 자동 생성하는 컬럼:
--   dbt_scd_id     : 각 버전 row의 surrogate key
--   dbt_valid_from : 이 버전이 유효해진 시점
--   dbt_valid_to   : 이 버전이 만료된 시점 (NULL = 현재 유효 = is_current)
--   dbt_updated_at : 스냅샷이 이 row를 본 시점
--
-- strategy='timestamp' : updated_at 컬럼 값이 바뀌면 "변경"으로 간주 (가장 빠름/권장).
--   updated_at이 없으면 strategy='check' + check_cols=[...] 로 컬럼값 비교.
--
-- 참고: dbt 1.9+에서는 이 config를 .yml(또는 config 블록)로 옮기는 것을 권장하지만,
--       가장 흔한 형태는 이 classic snapshot 블록이라 그대로 쓴다.
-- ============================================================================
{% snapshot snap_user_plan %}
{{
    config(
        target_schema='snapshots',
        unique_key='user_id',
        strategy='timestamp',
        updated_at='updated_at'
    )
}}

select
    user_id,
    plan_tier,
    cast(updated_at as timestamp) as updated_at
from {{ ref('users_raw') }}

{% endsnapshot %}
