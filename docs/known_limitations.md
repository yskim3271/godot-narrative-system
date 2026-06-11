# 알려진 한계 (1.2.0)

의도적 범위 제한(로드맵 항목)과 동작상 제약을 구분해 정리합니다.

## 저작 도구
- **노드 그래프 에디터**: 보기/추가/연결/삭제/시작 지정/배치 저장 + 인라인 편집(텍스트/화자/노드 id rename/선택지 텍스트·타깃) + undo/redo 지원. 한계 — 조건/액션/시퀀스·선택지 조건 편집과 **선택지 행 추가/삭제**는 Inspector 경유(❓⚡🎬 배지), Inspector에서의 구조 변경은 Refresh 필요. 상세: [graph_editor.md](graph_editor.md).
- **.ndlg 텍스트 포맷**은 대화 전용 — 캐릭터/퀘스트/변수/번역 테이블은 코드·Inspector로 저작 ([text_script.md](text_script.md)). 텍스트 임포트로 기존 대화를 교체하면 그래프 배치가 초기화됩니다(자동 배치로 복구).
- **에디터 미리보기(Preview 탭)는 시퀀서를 실행하지 않습니다** — 🎬 줄은 트랜스크립트에 로그만 (에디터엔 씬/액터/카메라가 없음). 연출 확인은 데모 씬 실행으로.
- **패널 CSV Export/Import는 첫 번째 번역 테이블(`localization_tables[0]`)만 다룹니다** — 다중 테이블은 코드/Inspector로.
- 검증·번역 이슈 더블클릭 포커스의 `where` 역파싱은 id 규약([a-zA-Z0-9_.])을 지키는 데이터 기준 — 규약 밖 문자(공백/따옴표)가 든 id는 `id_charset` 경고 대상이며 포커스가 실패할 수 있습니다(검증 자체는 정상).
- 에디터 플러그인 활성화 토글(`_enable_plugin`) 경로는 headless 자동화가 불가능해 수동 확인 대상입니다 (패널·그래프 탭·런타임·CLI·데모 부팅은 자동 검증됨).

## 대화 런타임
- **동시 대화 1개** — 실행 중 `start_dialogue()`는 거부됩니다. 인터럽트/스택은 미지원.
- 노드의 `next_node_id`는 "조건 스킵 대상"과 "advance 대상"을 겸합니다 — 인사 변형 같은 패턴은 [dialogue_authoring.md](dialogue_authoring.md)의 라우팅 패턴으로 해결.
- 대사 텍스트 인라인 마크업은 `[var=x]` 변수 치환만 지원(대사/선택지/바크/알림, 미선언 변수는 태그 원문 유지 + 검증기 경고). 그 외 `[color]` 등 BBCode는 RichTextLabel이 그대로 렌더링. Unity DS의 `[lua(...)]`식 표현식 치환은 없음.
- 언어 전환 시 표시 중 대사의 타자기 효과가 처음부터 재생됩니다.

## 퀘스트
- ~~반복·포기 없음~~ → 1.2.0에서 구현: `abandon_quest()`(active→inactive), `repeatable`(completed/failed에서 재시작, 완료 횟수 누적), objective `auto_complete_condition`, 카테고리. 남은 제약:
  - **objective 자동 완료 조건은 내러티브 변수가 바뀔 때 평가**됩니다 — `has_seen()`/외부 함수 등 변수 밖 상태가 바뀐 경우는 `recheck_auto_objectives()`를 직접 호출. 조건식에 상태를 바꾸는 함수(`complete_quest` 등)를 넣는 것은 지원 대상 아님(평가는 부수효과 없는 식이어야 함 — 검증기는 파스만 검사).
  - prerequisites는 **completed 상태만** 인정 — failed/abandoned 선행 퀘스트는 충족으로 치지 않음(의도).
  - 자동 완료 평가는 active 퀘스트만 대상(의도 — 진행은 active에서만).
- objective 완료 시 퀘스트 자동 완료 없음(의도) — `are_all_objectives_completed()`로 게임이 결정 (한 줄 글루: [quest_system.md](quest_system.md)).

## 저장
- **시퀀서 진행 상태는 저장되지 않습니다** — 로드 시 연출은 재생되지 않음(효과는 반영되어 있음). Unity DS와 동일 정책.
- 대화 히스토리는 상한(기본 200)까지만 보존.

## 시퀀서
- `@time`은 숫자 리터럴만(표현식 불가) — Unity DS와 동일. 시간 기준은 항상 "런 시작".
- 카메라 명령은 활성 카메라 1대 대상 — 다중 카메라/뷰포트 라우팅 없음. 3D `focus_camera`는 회전만(이동 없음, 이동은 `move_camera_3d`).
- 취소된 런의 진행 중 `wait()` 코루틴은 타이머 만료까지 컨텍스트를 참조합니다 — 게임에선 무해하나, 컨텍스트를 즉시 폐기하는 코드(테스트 등)는 최장 wait만큼 기다려야 종료 시 누수 진단이 없습니다. (`@message` 대기 줄은 취소 시 즉시 풀립니다.)
- `play_animation_wait`를 루프 애니메이션에 쓰면 영원히 대기합니다.

## UI
- 레퍼런스 품질(스타일 미적용) — 상용 게임은 교체/테마 적용 전제.
- BarkUI 3D 말풍선은 화면 공간 투영(깊이 가림 없음, 카메라 뒤면 숨김). 선택지 숫자 단축키 없음(포커스 네비게이션만).
- QuestLog: 트래커 토글·Abandon 버튼(`show_abandon_button`)·반복 완료 ×N 배지는 있지만, 정렬/필터/검색/카테고리 그룹핑 없음(카테고리는 조회 API로 자체 UI 구현 전제).

## 기타
- C# 전용 래퍼 API 없음 (GDScript API를 C#에서 호출하는 것은 가능).
- Yarn/Ink/articy 임포터 없음 (.ndlg 텍스트 포맷이 자체 저작 경로).
- 멀티플레이어 동기화 미고려.
