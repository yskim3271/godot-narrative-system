# 대화 저작 가이드

MVP의 저작 환경은 **Inspector 중심**입니다(노드 그래프 에디터는 로드맵 참고). 데이터 구조를 이해하면 Inspector만으로 충분히 빠르게 작업할 수 있고, 검증기가 실수를 잡아줍니다.

## 데이터 구조 한눈에

```
NarrativeDialogue (id, start_node_id)
 └─ nodes: NarrativeDialogueNode[]
     ├─ id, speaker_id, text
     ├─ conditions   ← false면 이 노드를 건너뛰고 next_node_id로 (스킵)
     ├─ actions      ← 노드 표시 직전에 실행 (변수 대입, start_quest(...) 등)
     ├─ sequencer_commands ← 대사와 병행 실행되는 연출 명령
     ├─ choices: NarrativeChoice[]  ← 있으면 선택 대기, 없으면 advance 대기
     └─ next_node_id ← advance 시 이동 (비우면 대화 종료)
```

- **링크는 전부 문자열 id**입니다. 오타는 런타임에 친절한 에러+대화 종료로 처리되고, 검증기가 사전에 잡습니다.
- 선택지의 `target_node_id`를 비우면 그 선택으로 **대화가 종료**됩니다.

## 실행 순서 (중요)

노드 진입 시: `node_entered` → **conditions 평가** (false → next로 홉) → **seen 기록** → **actions 실행** → 텍스트/선택지 해석 → `line_presented`(+`choices_presented`) → 시퀀서 시작.

조건이 seen 기록보다 **먼저** 평가되므로, 노드가 자기 자신에 대한 `not has_seen(...)` 조건을 가질 수 있습니다(아래 패턴).

## 패턴 모음

### 첫만남 / 재방문 인사 (데모에서 사용)
```
start_node_id = "g_return"

g_return:  conditions = has_seen("guard_talk", "g_first")
           text = "또 자네군."           next = "g_first"
g_first:   conditions = not has_seen("guard_talk", "g_first")
           text = "처음 보는 얼굴이군."   next = "g_menu"
g_menu:    (선택지들)
```
첫 방문: g_return이 스킵되어 g_first 표시 → advance → g_menu.
재방문: g_return 표시 → advance → g_first가 스킵되어 g_menu.

### 퀘스트 단계별 선택지 (한 메뉴에서 상태에 따라 다른 항목)
```
c_give:     condition = quest_state("rat_hunt") == "inactive"
c_progress: condition = is_quest_active("rat_hunt") and objective_count("rat_hunt", "kill_rats") < 5
c_done:     condition = is_quest_active("rat_hunt") and objective_count("rat_hunt", "kill_rats") >= 5
```

### 조건 미달 선택지를 회색으로 보여주기
`show_disabled = true` — 조건 실패 시 숨기는 대신 비활성으로 노출 ("통행료 (50골드)"처럼 동기 부여용).

### 대사 중 연출
```
sequencer_commands:
    set_expression("guard", "happy")
    play_animation("guard", "wave")
    wait(0.5)
    focus_camera("guard", 0.4)
```
시퀀스는 대사 표시와 **병행** 실행되며, 플레이어가 advance하면 자동 취소됩니다. → [sequencer.md](sequencer.md)

## 함정과 요령

1. **Inspector 배열 복제 = 인스턴스 공유.** 노드/선택지를 복제한 뒤 한쪽을 고치면 양쪽이 같이 바뀝니다. 복제 후 우클릭 → **Make Unique**. (검증기의 `shared_resource_instance` 에러)
2. **id 문자셋은 `[a-zA-Z0-9_.]`** — 공백·한글 id는 저장/로컬라이징 키에서 위험하므로 경고 처리됩니다. 표시용 텍스트는 자유.
3. **빈 condition은 항상 true**, 빈 next/target은 "종료"입니다.
4. **조건에 대입을 쓸 수 없습니다** — `gold = 10`은 파스 에러(아마 `==` 의도). 부수효과는 actions에.
5. 모든 선택지가 숨겨질 수 있는 노드는 경고가 뜨고 일반 대사처럼 advance로 진행됩니다 — 의도가 아니라면 무조건 선택지 하나를 두세요.
6. 대화 데이터를 코드로 만들고 싶다면 `examples/integrated_demo/db_builder.gd` 패턴(빌더 → `.tres` 생성 → 검증 게이트)을 참고하세요. 대량 콘텐츠에 특히 좋습니다.

## 검증 체크리스트

작업 후 **Narrative 패널 → Validate** (또는 CLI). 잡아주는 것: 시작 노드 누락, 끊어진 링크, 도달 불가 노드, 없는 캐릭터/퀘스트/변수/함수, 조건식 파스 에러(위치 포함), 중복 id, 공유 인스턴스, 누락 로컬라이징 키, 조건-스킵 무한 루프 후보.
