# M2 완결. 선택지 인라인 편집 + 인라인 마크업

## 목표
M2 잔여 두 항목을 마감한다: ① 그래프 에디터에서 선택지 텍스트/타깃을 캔버스에서 직접 편집(전부 undoable), ② 인라인 마크업 — `[var=x]` 런타임 치환 + 에디터 삽입 단축키 + 선택지 자동 넘버링. 치환이 없으면 `[var=x]` 헬퍼는 의미가 없으므로 런타임 치환을 함께 구현했다.

## 구현 내용
- **`runtime/text_markup.gd` (신규, @tool)**: `substitute_variables(text, state)` — 잘 구성된 `[var=name]`을 `str(state.get_value(name))`로 치환. 미선언 변수/빈 이름/닫는 괄호 없는 태그는 **원문 유지**(화면에서 바로 보임), 치환 값은 재스캔하지 않음(재귀 없음). `find_variable_tags(text)`는 검증기용.
- **치환 적용 지점** (로컬라이징 해석 **후** — 번역문에도 태그 사용 가능): 러너 `_resolve_node_text`/`_resolve_choice_text`(대사/선택지), 컨텍스트 `bark`/`request_alert`(바크/알림).
- **`validation/narrative_validator.gd`**: 노드/선택지 텍스트의 `[var=x]`가 미선언 변수를 참조하면 `markup_unknown_variable` 경고.
- **그래프 에디터 선택지 행(slots 2+)**: 읽기 전용 Label → **텍스트 입력칸 + 타깃 id 입력칸**. 텍스트는 `_ur_choice_text`(rebuild 없는 필드 동기, 화자/텍스트와 동일 패턴). 타깃은 **`_ur_link` 재사용**(포트 드래그와 같은 undo 경로) — 빈 값 = 대화 종료, 미지 노드 id는 거부+되돌림. `_ur_link`가 인라인 타깃 칸도 동기화하므로 포트 드래그·undo 시 칸이 따라 갱신됨. 필드 동기 로직은 `_sync_field_text`로 통합.
- **마크업 단축키** (텍스트 칸·선택지 텍스트 칸 내부, gui_input에서 accept_event로 처리): Ctrl+Shift+V = `[var=…]` 삽입(선택 영역이 변수명, 없으면 캐럿이 `]` 앞), Ctrl+Shift+C = `[color=yellow]…[/color]` 감싸기. `insert_var_markup`/`wrap_color_markup`은 public이라 headless 테스트가 키 이벤트 없이 호출.
- **선택지 자동 넘버링**: `GraphModel.toggle_choice_numbering`(순수 로직 — 전부 올바른 번호면 제거, 아니면 기존 접두 정규화 후 부여) + 에디터 `auto_number_selected_choices`(툴바 **1.2.3** 버튼 / 캔버스 Ctrl+Shift+N, 1 undo 단위 `_ur_choice_texts`).

## 발견된 문제
없음 — 수동 확인에서 신규 결함 발견되지 않음(함정 ⑧⑨ 회피 설계가 그대로 유효: 입력칸은 노드 본문에만 배치, 단축키는 포커스된 컨트롤이 소비).

## 생성/수정 파일
runtime/text_markup.gd(신규)·dialogue_runner.gd·narrative_context.gd, validation/narrative_validator.gd, editor/dialogue_graph_editor.gd·dialogue_graph_model.gd, tests/test_markup.gd(신규 7)·test_graph_undo.gd(+4)·test_graph_editor_ui.gd(+2)·test_graph_model.gd(+2)·test_validator.gd(+1), docs/graph_editor.md·dialogue_authoring.md·known_limitations.md·roadmap.md.

## 검증 방법 / 테스트 결과
- 전체 파이프라인 **ALL GREEN**: 유닛 **199/199 (5.3s, SCRIPT ERROR 0)** · 해피패스 순수성 클린 · 데모 DB strict 0/0 · 데모 5종 부팅 OK.
- markup 7종: 치환 기본/다중/트림/null state, 미지·빈 이름·미완성 태그 원문 유지, BBCode 통과, 재귀 없음, find_variable_tags, 러너 대사+선택지 치환, 바크/알림 치환.
- undo 4종: 선택지 텍스트 undo/redo(+칸 동기), 타깃 변경 undo(+캔버스 연결 복원), 미지 타깃 거부(무기록+되돌림), 자동 넘버링 undo/redo+토글 해제.
- editor_ui 2종: 선택지 칸 존재+포트 드래그 시 타깃 칸 동기+standalone 커밋, 마크업 삽입 캐럿 위치(TextEdit/LineEdit).
- model 2종 + validator 1종: 접두 strip/토글 순수 로직, markup_unknown_variable 경고.
- **실제 에디터 수동 확인(computer-use)**: 선택지 텍스트 편집+Enter 커밋+Ctrl+Z(칸 동기), 타깃 입력으로 연결 생성+미지 id 거부 상태줄+Ctrl+Z 복원, 텍스트 칸 안 Ctrl+Shift+V/C 삽입(에디터 전역 단축키 충돌 없음)+1 undo 복원, 1.2.3 버튼 넘버링+Ctrl+Shift+N 토글 해제. 데모 DB는 저장하지 않음(git 무변경 확인).

## 남은 한계
- 선택지 **추가/삭제**와 조건/액션은 여전히 Inspector(구조 변경 후 Refresh) — graph_editor.md에 문서화.
- `[var=x]`만 치환 — Unity DS의 `[lua(...)]`식 표현식 치환은 범위 외(known_limitations.md).

## 다음 단계
M3 — 시퀀서 `@time` 병렬 스케줄링 + `->message` 동기화, Camera3D/3D bark (같은 세션 B 작업).
