# M2 후속. 그래프 에디터 인라인 편집 + 노드 rename 링크 추적

## 목표
그래프 노드의 화자·텍스트를 캔버스에서 바로 편집하고, 노드 id rename 시 그 id를 가리키던 모든 링크(next/choice/start)를 자동 추적하도록 한다. 편집 로직은 모델/핸들러 수준에서 headless 테스트로 고정하고, 실제 에디터에서 조작감을 수동 확인한다. (이 세션은 먼저 1.0.0 수동 확인을 수행 — 결과·발견 버그는 test_report.md 참조.)

## 구현 내용
- **`editor/dialogue_graph_model.gd` · `rename_node(dialogue, old_id, new_id)`** (순수 로직, headless 테스트): new_id 검증(문자셋·중복) 후 `node.id`를 바꾸고 모든 노드의 `next_node_id`·`choice.target_node_id`와 `start_node_id`를 old→new로 재타깃. `{renamed, retargeted, error}` 반환. **대칭 설계** — `rename(new→old)`이 정확한 역연산이라 에디터 undo가 이를 그대로 사용(단 *이미 끊긴 링크*가 new_id를 가리키던 극단적 경우만 비대칭).
- **`resources/dialogue_resource.gd` · `invalidate_index()`**: id 인덱스 캐시는 `nodes.size()` 변화로만 자동 재빌드되어 **in-place id 변경(rename)을 놓침** → 명시적 무효화 메서드 추가, `rename_node`가 호출. (잠복 버그: 어떤 코드든 node.id를 직접 바꾸면 캐시가 어긋났음.)
- **`editor/dialogue_graph_editor.gd` 인라인 편집 UI** (전부 undoable):
  - 노드 **헤더 행(slot 0)** = id 입력칸(rename) + 화자 입력칸 + ❓⚡🎬 배지. 제목은 id 읽기 전용(▶ 시작 표시).
  - **slot 1** = 여러 줄 텍스트 편집칸.
  - 포커스 진입 시 이전 값 캡처 → 포커스 이탈/Enter 시 1회 편집을 1 undo 단위로 커밋(`_commit_field`/`_commit_rename`).
  - `_ur_set_field`는 전체 rebuild 없이 모델+해당 칸만 갱신(다음에 클릭한 칸이 파괴되지 않도록), `_ur_rename`은 rebuild. rename 거부 시 칸 되돌림+상태 표시.
  - 포트 계약(slot 0=header, slot 1=text, slots 2+=choice)은 그대로 유지.

## 발견된 문제 (해결됨)
1. **id 인덱스 캐시 미무효화**: rename 후 `has_node_id(new)`가 false, `get_node_by_id(new)`가 null — 캐시가 size 변화로만 재빌드되기 때문. 모델 테스트가 즉시 표면화 → `invalidate_index()` 추가로 해결(잠복 버그 동시 수정).
2. **타이틀바 자식 컨트롤은 포커스를 못 받음**: 처음엔 id 입력칸을 GraphNode 타이틀바에 두었으나, 클릭이 노드 드래그/선택 제스처에 먹혀 입력칸이 포커스되지 않고 에디터 전역 단축키(Ctrl+A=Add Node)가 발동 — **실제 에디터 수동 확인에서만 드러남**(headless·본문 컨트롤 테스트는 통과). → id 입력칸을 노드 **본문 헤더 행**으로 이동(본문 컨트롤은 정상 포커스). 함정 ⑧(EXPAND_FILL)에 이은 "에디터 컨텍스트 전용 결함" 두 번째 사례.

## 생성/수정 파일
editor/dialogue_graph_editor.gd(인라인 편집/rename UI·핸들러·_ur 메서드)·dialogue_graph_model.gd(rename_node), resources/dialogue_resource.gd(invalidate_index), tests/test_graph_model.gd(+4 rename)·test_graph_undo.gd(+4 인라인/rename undo)·test_graph_editor_ui.gd(+1 standalone rename, 시작표시 어서션 정리), docs/graph_editor.md·roadmap.md(갱신).

## 검증 방법 / 테스트 결과
- 전체 파이프라인 **ALL GREEN**: 유닛 **184/184 (5.1s, SCRIPT ERROR 0)** · 해피패스 순수성 클린 · 데모 DB strict 0/0 · 데모 5종 부팅 OK.
- 모델 4종: choice/next/start 재타깃 카운트, 거부(중복/문자셋/미지/무변경), **undo 대칭**(rename→역rename이 정확 복원).
- undo 4종: 텍스트·화자 편집 undo/redo(+칸 동기), 동값 편집 무기록, rename undo/redo(링크 복원+캔버스 remap), 중복 rename 거부(무기록+칸 되돌림).
- editor_ui 1종: undo 매니저 없는 standalone 경로에서도 rename이 모델 변경+링크 재타깃.
- **실제 에디터 수동 확인(computer-use)**: 텍스트 인라인 편집+Ctrl+Z, 헤더 id 칸 rename(`g_menu`→`g_hub`)으로 incoming+5 choice 링크 전부 추적 확인+Ctrl+Z 복원, 화자 편집. (데모 DB는 저장하지 않고 복원.)

## 남은 한계 (graph_editor.md에 문서화)
- 선택지 텍스트/타깃 인라인 편집 미지원(Inspector 경유). 조건/액션/시퀀스도 Inspector(❓⚡🎬 배지로 표시).
- 끊긴 링크가 가리키던 id로 rename 시 그 링크가 새 노드에 연결되는 비대칭(극히 드묾, Validate가 끊긴 링크를 잡아줌).

## 다음 단계 (제안)
M2 잔여(선택지 인라인 편집·인라인 마크업 헬퍼), 또는 M3(시퀀서 @time 병렬), 또는 Asset Library 배포 패키징 — 사용자 우선순위에 따라.
