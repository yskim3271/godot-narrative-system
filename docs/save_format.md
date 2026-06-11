# 저장 포맷 사양 (save_version 2)

저장 파일은 `user://saves/<slot>.json`에 **사람이 읽을 수 있는 UTF-8 JSON**(탭 들여쓰기)으로 기록된다. `.tres`/`str_to_var` 기반 직렬화는 보안상(스크립트 임베드 = 임의 코드 실행) 사용하지 않는다 — 로드는 `JSON.parse_string` 단일 경로.

## 1. 스키마

```jsonc
{
  "save_version": 2,                  // int, 필수. 마이그레이션 기준. 현재보다 크면 로드 거부
  "plugin_version": "0.1.0",          // 진단용 (분기 금지)
  "saved_at": "2026-06-11T12:34:56Z", // ISO 8601 UTC — 사람 가독성
  "saved_at_unix": 1781181296,        // 슬롯 정렬용
  "language": "ko",                   // LocalizationManager로 복원
  "variables": {                      // String → null|bool|number|String
    "player.gold": 25, "met_guard": true
  },
  "quests": {                         // 손대지 않은 inactive 퀘스트는 기록하지 않음
    "find_sword": {
      "state": "active",              // "inactive"|"active"|"completed"|"failed" (부재=inactive)
      "tracked": true,                // QuestTracker HUD 표시 여부
      "objectives": { "kill_rats": { "count": 3, "completed": false } },
      "completions": 0                // v2: 완료 횟수 (반복 퀘스트). abandon 후에도 보존
    }
  },
  // "state": "inactive" 항목은 완료 이력이 있는 퀘스트를 abandon했을 때만 존재
  // (completions를 보존하기 위함; objectives는 비어 있음)
  "dialogue": {
    "seen_nodes": { "guard_intro": ["n2", "start"] },   // 정렬 배열 — diff 안정성
    "history": [ { "d": "guard_intro", "n": "start", "t": 1781181200 } ],  // 상한 settings.history_limit(기본 200)
    "current": {                      // 진행 중 대화 없으면 null
      "dialogue_id": "guard_intro", "node_id": "n4",
      "phase": "at_line"              // "at_line" | "at_choices"
    }
  },
  "custom": {}                        // 게임 소유 JSON-safe 데이터 (Narrative.state.custom_data)
}
```

## 2. 쓰기 경로 (원자성)

1. 직렬화 → `<slot>.json.tmp`에 기록
2. 기존 `<slot>.json` → `<slot>.json.bak`으로 회전 (직전 정상본 1개 보존)
3. tmp → `<slot>.json` rename

러너가 트랜지션 처리 중(`_busy`)이면 `save_game()`은 `ERR_BUSY` 반환 (액션 내부에서 저장 호출 방지). 라인/선택지 대기 상태에서는 항상 안전.

## 3. 읽기 경로 (방어)

- JSON 파스 실패 → 파일을 `<slot>.json.corrupt-<unix>`로 격리, `push_error`, `ERR_FILE_CORRUPT` 반환, **기존 런타임 상태는 그대로 유지**
- `save_version > 현재` → 로드 거부 (다운그레이드 빌드가 새 저장을 망치지 않도록)
- 섹션별 방어적 타입 체크: 깨진 섹션만 기본값으로 리셋+경고, 나머지는 계속 로드
- JSON 숫자는 전부 float로 도착 → 선언된 `VariableResource.type` 기준으로 int 복원, objective count는 `int()`+`[0, target_count]` 클램프
- 미선언 변수 키는 그대로 보존+경고 (관용적 로드)

## 4. 마이그레이션

`runtime/save_migrations.gd`에 `Dictionary[int, Callable]` 레지스트리:

```
while data.save_version < CURRENT_SAVE_VERSION:
    data = migrations[data.save_version].call(data)   # 단계 누락 시 로드 거부
    data.save_version += 1
```

스키마 변경 시 절차: `version.gd`의 `SAVE_VERSION` 증가 → 마이그레이션 함수 추가 → 구버전 픽스처로 테스트 추가.

### 이력

| 버전 | 변경 | 마이그레이션 |
|---|---|---|
| 1 | 최초 스키마 | — |
| 2 | 퀘스트 항목에 `completions` 추가, abandon된 퀘스트의 `"state": "inactive"` 항목 허용 (M3-2 반복 퀘스트) | 1→2: 모든 퀘스트 항목에 `completions: 0` 백필 |

## 5. 대화 재개(try_resume) 규칙

- `current`의 dialogue/node가 현재 DB에 존재하면: **표현만 재생** — 텍스트 재해석, 선택지 조건 재평가, `dialogue_resumed(dialogue_id, node_id)` → `line_presented`(/`choices_presented`) 방출. **노드 액션·시퀀서는 재실행하지 않음** (효과는 이미 저장된 변수/퀘스트에 있음)
- DB 변경으로 노드가 사라졌으면: 경고+`current` 폐기 (대화 미진행 상태로 정상 복귀)
- `at_choices`였는데 보이는 선택지가 0개가 됐으면 `at_line` 의미론으로 강등
