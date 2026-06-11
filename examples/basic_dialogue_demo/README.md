# Basic Dialogue Demo

**가장 작은 구성**의 대화 데모입니다 — 코드로 만든 데이터베이스, NPC 하나, 선형 3줄 대화.

- 조작: 방향키 이동 · **E** 대화 · Enter/Space/클릭으로 진행
- 핵심 코드: [basic.gd](basic.gd)의 `_build_database()` — `NarrativeDatabase`/`NarrativeDialogue`/`NarrativeDialogueNode`를 코드로 조립하고 `Narrative.load_database()`로 로드합니다 (프로젝트 설정 없이도 동작하는 경로)
- UI는 `addons/narrative_system/ui/dialogue_box.tscn`/`choice_list.tscn` 인스턴스 두 개가 전부 — autoload에 자동 연결됩니다

다음 단계: [branching_choice_demo](../branching_choice_demo/README.md) (선택지·조건·.ndlg 텍스트 저작)
