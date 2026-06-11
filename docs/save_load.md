# 저장 / 불러오기

## 사용법

```gdscript
Narrative.save_game()            # user://saves/save.json
Narrative.save_game("slot2")     # user://saves/slot2.json
Narrative.load_game("slot2")     # 상태 복원 + 진행 중이던 대화 위치 재개
Narrative.has_save("slot2")
Narrative.delete_save("slot2")
```

반환값은 Godot `Error` — `OK`, `ERR_BUSY`(아래), `ERR_FILE_NOT_FOUND`, `ERR_FILE_CORRUPT`, `ERR_INVALID_DATA`(버전 문제).

## 무엇이 저장되나

변수(persistent=false 제외) · 퀘스트 상태+objective 진행+추적 여부 · 본 노드(seen) · 대화 히스토리(상한 200) · **진행 중 대화 위치**(어느 대화/노드/라인·선택지 단계) · 현재 언어 · 게임 커스텀 데이터.

게임 자체 데이터(플레이어 위치 등)는 같은 파일에 실을 수 있습니다:
```gdscript
Narrative.context.state.custom_data["player_pos"] = [player.position.x, player.position.y]
Narrative.save_game()
# 로드 후: Narrative.context.state.custom_data.get("player_pos")
```
(JSON-safe 값만: null/bool/숫자/문자열/배열/딕셔너리)

## 대화 도중 저장과 재개

- **라인 표시 중·선택지 표시 중 저장은 항상 안전**합니다. 단, 시그널 핸들러/액션 "내부"(트랜지션 처리 중)에서는 `ERR_BUSY`로 거부됩니다.
- 로드 시 진행 중이던 대화는 **표현만 재생**됩니다: 텍스트 재해석 + 선택지 조건 재평가 + `dialogue_resumed` → `line_presented`(/`choices_presented`). **노드 액션과 시퀀서는 재실행되지 않습니다** (효과는 이미 저장된 변수/퀘스트에 들어있으므로 — 재실행하면 이중 지급이 됩니다).
- 저장 후 데이터베이스가 바뀌어 해당 노드가 사라졌다면: 경고 후 대화 위치만 폐기하고 나머지는 정상 로드.

## 안전장치 (자동)

- **원자적 쓰기**: 임시 파일 → 교체, 직전 정상본은 `.bak`으로 1개 보존
- **손상 격리**: 파싱 불가 파일은 `*.corrupt-<unix>`로 옮기고 기존 상태 무손상
- **버전 보호**: 파일의 `save_version`이 빌드보다 새로우면 로드 거부(다운그레이드 보호), 오래됐으면 마이그레이션 체인 적용
- **방어적 로드**: 섹션/항목 단위 타입 검사 — 깨진 부분만 기본값/드롭하고 나머지는 로드, objective 카운트는 DB 기준 재클램프
- 저장 파일은 **순수 JSON** — 로드 과정에서 어떤 리소스/스크립트도 로드하지 않습니다 (보안: [security_notes.md](security_notes.md))

## 스키마가 바뀔 때 (개발자)

1. `version.gd`의 `SAVE_VERSION` 증가
2. `runtime/save_migrations.gd`에 `이전버전 → Callable(data)->data` 단계 추가
3. 구버전 픽스처로 회귀 테스트 추가

필드별 스키마 정의: **[save_format.md](save_format.md)**
