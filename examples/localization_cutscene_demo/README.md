# Localization + Cutscene Demo

런타임 언어 전환과 시퀀서 컷신, bark를 한 화면에서 보여줍니다.

- **K** — 한국어 ↔ English 전환: 표시 중인 대사·화자명·HUD·bark까지 즉시 전환됩니다. ko는 인라인 원문, en은 관례 키(`dlg.bard_show.intro.text` 등) 테이블 — [docs/localization.md](../../docs/localization.md)의 계층 해석 그대로입니다.
- 음유시인(보라)에게 **E** — 두 번째 노드의 `sequencer_commands`가 대사와 병행 실행됩니다:
  `play_animation → wait → focus_camera(카메라 팬) → emit_signal("flourish") → 카메라 복귀` (시그널은 콘솔에 출력 — 게임 연동 지점)
- 대화하지 않는 동안 3.5초마다 머리 위 **bark** 말풍선 (`NarrativeActor`로 등록된 노드에 부착)
- Enter로 대사를 넘기면 진행 중인 컷신은 자동 취소됩니다 (연출이 입력을 막지 않음)

시퀀서 명령 레퍼런스: [docs/sequencer.md](../../docs/sequencer.md)
