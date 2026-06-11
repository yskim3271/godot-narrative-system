# 알려진 한계 (0.1.0 MVP)

의도적 범위 제한(로드맵 항목)과 동작상 제약을 구분해 정리합니다.

## 저작 도구
- **노드 그래프 에디터(0.2.0-dev)**: 보기/추가/연결/삭제/시작 지정/배치 저장 지원. 한계 — **undo/redo 없음**, 필드 편집은 Inspector 경유, Inspector에서의 구조 변경은 Refresh 필요, 노드 id rename 시 링크 자동 추적 없음(Validate로 확인). 상세: [graph_editor.md](graph_editor.md).
- 텍스트 스크립트 포맷(.dialogue류) 파서 없음 — 대량 저작은 `db_builder.gd` 코드 패턴 권장.
- 에디터 플러그인 활성화 토글(`_enable_plugin`) 경로는 headless 자동화가 불가능해 수동 확인 대상입니다 (패널·그래프 탭·런타임·CLI는 자동 검증됨).

## 대화 런타임
- **동시 대화 1개** — 실행 중 `start_dialogue()`는 거부됩니다. 인터럽트/스택은 미지원.
- 노드의 `next_node_id`는 "조건 스킵 대상"과 "advance 대상"을 겸합니다 — 인사 변형 같은 패턴은 [dialogue_authoring.md](dialogue_authoring.md)의 라우팅 패턴으로 해결.
- 대사 텍스트 인라인 마크업(`[var=x]` 치환 등) 미지원 — BBCode는 RichTextLabel이 그대로 렌더링하므로 사용 가능.
- 언어 전환 시 표시 중 대사의 타자기 효과가 처음부터 재생됩니다.

## 퀘스트
- completed/failed는 종결 상태 — 반복(데일리)·포기(abandon) 상태 없음.
- objective 완료 시 퀘스트 자동 완료 없음(의도) — `are_all_objectives_completed()`로 게임이 결정.
- objective 자동 완료 조건식(스펙의 objective condition 필드)은 미구현.

## 저장
- **시퀀서 진행 상태는 저장되지 않습니다** — 로드 시 연출은 재생되지 않음(효과는 반영되어 있음). Unity DS와 동일 정책.
- 대화 히스토리는 상한(기본 200)까지만 보존.

## 시퀀서
- 순차 실행 + `wait()`만 — Unity DS식 `@time` 병렬 스케줄링/`->Message` 동기화 없음.
- `move_camera`/`focus_camera`는 **2D 전용** (Camera3D 미지원).
- 취소된 런의 진행 중 `wait()` 코루틴은 타이머 만료까지 컨텍스트를 참조합니다 — 게임에선 무해하나, 컨텍스트를 즉시 폐기하는 코드(테스트 등)는 최장 wait만큼 기다려야 종료 시 누수 진단이 없습니다.
- `play_animation_wait`를 루프 애니메이션에 쓰면 영원히 대기합니다.

## UI
- 레퍼런스 품질(스타일 미적용) — 상용 게임은 교체/테마 적용 전제.
- BarkUI는 2D(Node2D 부착) 전용. 선택지 숫자 단축키 없음(포커스 네비게이션만).
- QuestLog의 트래커 토글 외 정렬/필터/검색 없음.

## 기타
- C# 전용 래퍼 API 없음 (GDScript API를 C#에서 호출하는 것은 가능).
- Yarn/Ink/articy 임포터 없음.
- 데모는 통합형 1개 (4분할 데모는 M2).
- 멀티플레이어 동기화 미고려.
