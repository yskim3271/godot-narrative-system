# Quest Demo

퀘스트 전체 사이클: **대화로 수주 → 월드에서 objective 진행 → 보고로 완료 → 보상**.

- 약사(보라색)에게 **E** — 첫 대화에서 퀘스트 수주 (`start_quest` 액션 + 알림)
- 약초(녹색) 3개를 밟아 채집 — `update_objective`가 트래커 HUD를 갱신하고, 약초 가시성은 objective 진행에서 **파생**됩니다(데이터와 월드가 항상 일치)
- **J** 로 퀘스트 로그(설명/목표/트래커 토글) 확인
- 다시 약사에게 — 진행 중이면 독촉, 3/3이면 완료 + 보상(`complete_quest` + rewards DSL)
- 핵심 패턴: [quest.gd](quest.gd)의 대화는 **조건-스킵 체인**(give→progress→done→after) — 퀘스트 상태에 맞는 첫 노드가 자동 선택됩니다

자세한 퀘스트 시스템 문서: [docs/quest_system.md](../../docs/quest_system.md)
