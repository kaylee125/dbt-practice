# dbt 실습 — Snapshot(SCD2) & Incremental

> 목적: **SCD Type 2 / snapshot** 과 **incremental + late-arriving** 을
> 말이 아니라 **직접 손으로 돌려보고 눈으로 확인**하기 위한 독립 미니 프로젝트.
> DuckDB(로컬 파일 `dev.duckdb`) 기반 — 외부 warehouse·크레덴셜 불필요.

## 0. 준비 (이미 완료됨)
- 격리된 venv(`.venv`)에 dbt-core 1.11 + dbt-duckdb 설치됨.
- 편의 alias (매번 입력 줄이기):
```bash
cd /path/to/dbt-practice
alias d=".venv/bin/dbt"          # 이후 `d run` 처럼 사용
# 모든 명령에 --profiles-dir . 가 필요 (profiles.yml이 프로젝트 폴더에 있어서)
```
> DuckDB 파일은 한 번에 한 프로세스만 연다. 쿼리 확인용 파이썬을 켜둔 채 `dbt`를 돌리면 lock 에러가 나니, 둘을 번갈아 실행할 것.

---

## 실습 A — Snapshot / SCD Type 2 (갭 #1)

### A-1. 최초 적재
```bash
.venv/bin/dbt seed     --profiles-dir .   # users_raw.csv → 테이블
.venv/bin/dbt snapshot --profiles-dir .   # SCD2 이력 테이블 생성
```
확인:
```bash
.venv/bin/python3 -c "import duckdb; [print(r) for r in duckdb.connect('dev.duckdb').execute('select user_id, plan_tier, dbt_valid_from, dbt_valid_to from snapshots.snap_user_plan order by user_id').fetchall()]"
```
기대 출력 — 3명 모두 `dbt_valid_to = None`(현재 유효):
```
('u1', 'free', 2026-01-01 00:00:00, None)
('u2', 'pro',  2026-01-05 00:00:00, None)
('u3', 'free', 2026-01-10 00:00:00, None)
```

### A-2. 변경 발생 → 이력 보존 확인 (핵심)
`seeds/users_raw.csv`에서 **u1을 `free` → `pro`로 바꾸고 `updated_at`을 미래로 갱신**:
```
u1,pro,2026-03-01 00:00:00
```
(`strategy='timestamp'` 이므로 `updated_at`이 바뀌어야 변경으로 감지됨)

다시 적재:
```bash
.venv/bin/dbt seed --full-refresh --profiles-dir .   # CSV 다시 로드
.venv/bin/dbt snapshot --profiles-dir .              # 변경 감지 → 새 버전 row
```
확인:
```bash
.venv/bin/python3 -c "import duckdb; [print(r) for r in duckdb.connect('dev.duckdb').execute('select user_id, plan_tier, dbt_valid_from, dbt_valid_to from snapshots.snap_user_plan order by user_id, dbt_valid_from').fetchall()]"
```
기대 출력 — **u1이 두 줄. 옛 free는 닫히고(`valid_to` 채워짐), 새 pro가 현재(None):**
```
('u1', 'free', 2026-01-01 00:00:00, 2026-03-01 00:00:00)   ← 과거 버전, 닫힘
('u1', 'pro',  2026-03-01 00:00:00, None)                  ← 현재 버전
('u2', 'pro',  2026-01-05 00:00:00, None)
('u3', 'free', 2026-01-10 00:00:00, None)
```

### A-3. 한 문장 요약
> "source는 row를 덮어써서 과거 plan이 사라진다. dbt snapshot이 변경을 감지할 때마다 새 row와 `dbt_valid_from/to`를 자동 관리해 **SCD Type 2 이력**을 만든다. fact를 `valid_from <= event_at < valid_to`로 join하면 **거래 시점의 plan_tier**를 정확히 붙일 수 있다. 전략은 `updated_at`이 있으면 `timestamp`, 없으면 `check` + `check_cols`."

---

## 실습 B — Incremental + late-arriving (갭 #4)

### B-1. 최초 적재 (full load)
```bash
.venv/bin/dbt run --select fct_events_incremental --profiles-dir .
.venv/bin/python3 -c "import duckdb; print('count =', duckdb.connect('dev.duckdb').execute('select count(*) from main.fct_events_incremental').fetchone()[0])"
```
기대: `count = 4` (e1~e4 전부). 최초 실행은 `is_incremental()`이 False라 전체 적재.

### B-2. 신규 + 늦게 도착한 과거 데이터 추가 (핵심)
`seeds/events_raw.csv`에 두 줄 추가:
```
e5,u2,open,2026-05-03 08:00:00    ← 정상 신규 (현재 max=05-02 이후)
e6,u1,edit,2026-05-01 23:00:00    ← LATE-ARRIVING: 05-01 이벤트가 늦게 도착
```
다시 적재 + 증분 실행:
```bash
.venv/bin/dbt seed --full-refresh --profiles-dir .
.venv/bin/dbt run --select fct_events_incremental --profiles-dir .
.venv/bin/python3 -c "import duckdb; print('count =', duckdb.connect('dev.duckdb').execute('select count(*) from main.fct_events_incremental').fetchone()[0])"
```
기대: `count = 6`. **e5(신규)뿐 아니라 e6(과거 지각 도착)도 들어옴.**

### B-3. 왜 e6가 잡혔나 (직접 비교해볼 것)
- 모델의 증분 필터: `where event_at > (select max(event_at) - interval '3 days' from {{ this }})`
- 순진한 버전 `> max(event_at)` 이었다면 e6(05-01)는 max(05-02)보다 과거라 **영원히 누락**.
- **lookback window(3일)** 덕분에 max 근처 과거를 재처리 → e6 포착.
- 재처리해도 `unique_key='event_id'` + `delete+insert` 전략이라 e1~e4 **중복 안 생김**.
- 실험: 모델에서 `- interval '3 days'`를 지우고 B-2를 다시 해보면 e6가 안 들어온다(= 갭의 실체). `target/compiled/dbt_practice/models/marts/fct_events_incremental.sql`에서 dbt가 실제로 만든 SQL도 열어볼 것.

### B-4. 한 문장 요약
> "incremental은 매번 풀 빌드 대신 신규/변경분만 적재한다. `is_incremental()` 블록에서 마지막 적재 시점 이후만 거른다. 단 `> max`만 쓰면 늦게 도착한 과거 데이터를 놓치므로 **lookback window**로 max 근처를 재처리하고, `unique_key` + `delete+insert`(또는 merge)로 중복을 막는다. **이게 내 Spectrum 87% 누락 사고의 본질** — Amplitude 도착 윈도우를 잘못 모델링한 거였다."

---

## 초기화 / 재시작
```bash
./reset.sh        # dev.duckdb·target 삭제 + 시드 CSV 초기값 복원 → 처음부터 다시
```

## 파일 지도
| 파일 | 무엇 |
|------|------|
| `seeds/users_raw.csv` | 스냅샷 입력 (변경해서 SCD2 트리거) |
| `seeds/events_raw.csv` | 증분 입력 (추가해서 late-arriving 실험) |
| `snapshots/snap_user_plan.sql` | SCD Type 2 — 주석에 컬럼/전략 설명 |
| `models/marts/dim_user_plan_history.sql` | 스냅샷 소비 dim (valid_from/to/is_current) |
| `models/marts/fct_events_incremental.sql` | 증분 + lookback — 주석에 전략 설명 |

