-- 스냅샷(SCD Type 2)을 소비하는 dimension.
-- 1 row = 한 유저의 한 plan 유효구간. 과거 시점의 plan_tier를 정확히 복원할 수 있다.
--   "fct를 valid_from <= event_at < valid_to 로 join하면 거래 시점 차원값을 붙인다"
--   가 핵심 설명 포인트.
select
    user_id,
    plan_tier,
    dbt_valid_from                as valid_from,
    dbt_valid_to                  as valid_to,
    (dbt_valid_to is null)        as is_current
from {{ ref('snap_user_plan') }}
order by user_id, valid_from
