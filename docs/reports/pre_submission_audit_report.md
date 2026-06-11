# 제출 전 전수 감사 보고서 (1.2.0)

날짜: 2026-06-11 · 방식: 독립 관점 4개(문서↔코드 대조 / 코드 레벨 미구현 헌트 / M2-2·M3-2 적대적 엣지 분석 / 패키징 준비)로 병렬 조사 후, 모든 주장에 대해 코드 근거로 재검증.

## 결론

- **문서가 약속한 기능은 100% 구현 확인** — 파사드 52 메서드·시그널 16종·DSL 함수 15종·시퀀서 명령 16종·검증기 상수 3자 동기화 전수 대조, 불일치 0건.
- 실결함 **3건 발견 → 전부 수정** (아래 §1).
- 버전 정책 문제 1건(제출 차단급) → **1.2.0 릴리스로 해소** (§2).
- 의도된 한계는 known_limitations.md에 최신화(특히 1.0.0 시절의 "abandon/반복/자동완료 미구현" 구절이 stale였음 — 갱신).
- 조사 단계에서 제기된 나머지 주장 11건은 재검증 결과 **기각**(§4 — 코드 근거 포함).

## 1. 수정한 실결함

| # | 결함 | 수정 |
|---|---|---|
| 1 | Preview 탭이 `objective_completed` 시그널을 배선하지 않아 목표 단위 완료가 트랜스크립트에 안 보임 | `🎯 objective 'q / o' completed` 로그 추가 + 테스트 |
| 2 | 패널 **CSV Import 후 Preview 탭의 언어 목록이 stale** (새 로케일을 임포트해도 미리보기 언어 셀렉터에 안 나타남) | import 핸들러가 `_preview.set_database(_db)`도 호출 |
| 3 | QuestLog 레퍼런스 UI가 M3-2 런타임 API를 전혀 반영 안 함 (abandon/완료 횟수) | 진행 중 퀘스트에 **Abandon 버튼**(`show_abandon_button`, 키 `ui.quest_log.abandon`, 파사드에 abandon_quest 없으면 자동 숨김) + **반복 완료 ×N 배지**(2회째부터) + 테스트 3종 |

## 2. 패키징/버전 (제출 차단 해소)

- v1.1.0 태그 이후 main에 M2-2/M3-2가 쌓였고 `SAVE_VERSION`이 2로 올라간 상태에서 VERSION이 1.1.0에 머물러 있었음 → **1.2.0으로 릴리스 확정**: plugin.cfg·version.gd·CHANGELOG 3곳 동기화, 영문 README 기능 목록에 M2-2/M3-2 반영.
- `git archive` 패키지 구성 재확인: addons/narrative_system/만 포함(tests/·docs/·examples/·project.godot 제외), LICENSE·영문 README 포함, addons/ 코드에 `res://examples` 등 외부 경로 참조 없음(테스트 전용 참조는 export-ignore로 제외됨).

## 3. 문서로 명시한 의도된 한계 (이번에 known_limitations.md 갱신)

- Preview는 시퀀서를 실행하지 않음(🎬 로그만) — 에디터엔 씬/액터 없음.
- 패널 CSV 왕복은 `localization_tables[0]`만 대상.
- objective 자동 완료 조건은 **변수 변경 시** 평가(그 외 상태는 `recheck_auto_objectives()` 수동 호출), 조건식은 부수효과 없는 식 전제, active 퀘스트만 대상.
- prerequisites는 completed만 인정. objective 모두 완료돼도 퀘스트 자동 완료 없음(의도).
- 그래프 에디터에서 선택지 행 추가/삭제는 Inspector 경유.
- `parse_where` 역파싱은 id 규약([a-zA-Z0-9_.]) 준수 데이터 기준(규약 밖 id는 `id_charset` 경고 대상).
- QuestLog에 카테고리 그룹핑/정렬/검색 없음(조회 API로 자체 UI 전제). `.ndlg`는 대화 전용(퀘스트 정의 미포함). 리소스 `metadata`는 자유 확장용(런타임은 graph_position만 사용).

## 4. 기각한 주장 (재검증 근거)

| 주장 | 기각 근거 |
|---|---|
| `open_dialogue`의 auto_layout이 수동 배치를 초기화 | `dialogue_graph_model.gd:292` — `has_position(node)`면 skip. 저장된 위치는 불변 |
| 미리보기 재시작 시 시그널 중복 연결 | `start_preview()`가 항상 `stop_preview()`로 컨텍스트 폐기 후 새 컨텍스트에 연결. GDScript에 예외 없음 — 부분 연결 경로 부재 |
| repeatable 재시작 시 auto_track 미재적용 | `start_quest()`가 항목 전체를 새로 생성(`"tracked": quest.auto_track`) — 재적용됨. 테스트로도 확인 가능 |
| BBCode 이스케이프가 `[`만 처리해 불완전 | RichTextLabel 태그는 `[`로만 열림 — `[`→`[lb]` 치환으로 충분. `]` 단독은 불활성 |
| localization 리포트가 fallback 언어를 오산 | 폴백으로 "구제"되는 키도 해당 로케일 번역이 없는 것은 사실 — 커버리지 도구로서 올바른 표기(기본 언어 인라인 커버는 별도 규칙으로 처리 중) |
| `set_database(null)` 후 Start 시 비정상 | `_selected_dialogue()==""` → "no dialogue selected" 에러 상태로 정상 처리 |
| focus_node의 zoom 보정 산식 오류 | `pos*zoom - (size - node_size*zoom)*0.5` — scroll_offset(줌 적용 픽셀) 대수와 일치, zoom=1 수동 검증 통과 |
| v1→v2 마이그레이션이 v1의 inactive 항목을 못 다룸 | v1에는 abandon이 없어 inactive 항목이 존재할 수 없음. 존재해도 sanitize가 기본값 처리 |
| 비active 퀘스트 자동 완료 미평가는 버그 | 의도 — 진행은 active에서만. 문서화함 |
| 로드 시 기형 objective 값이 조용히 드롭 | 의도된 관용 로드(부분 진행으로 강등) — test_save_hardening이 커버 |
| bark_requested 미리보기 미배선 | bark는 DSL 함수/시퀀서 명령이 아니라 게임 코드 API(`Narrative.bark()`) 전용 — 미리보기에서 발생 경로 자체가 없음(죽은 배선이 됨) |

## 5. 검증

수정 반영 후 `.\scripts\run_tests.ps1` 전체 파이프라인 ALL GREEN (유닛 252 + 해피패스 순수성 + 데모 DB strict + 데모 5종 부팅). 상세 카운트: [test_report.md](../test_report.md).
