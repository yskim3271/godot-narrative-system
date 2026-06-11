# 대화 그래프 에디터

에디터 상단의 **Narrative** 메인 스크린 탭(2D/3D/Script 옆)에서 대화를 노드 그래프로 보고 편집합니다. 데이터베이스는 `narrative_system/database_path` 프로젝트 설정에서 읽습니다(하단 Narrative 패널에서 Load하면 자동 설정).

## 화면 구성

- **툴바**: 대화 선택 드롭다운 · New Dialogue · Add Node · Set Start · Delete · Save · Validate · Refresh · 상태 표시
- **캔버스(GraphEdit)**: 줌/팬 기본 지원. 노드마다 —
  - 제목 = 노드 id (시작 노드는 `▶ ` 접두)
  - 헤더 행: 화자 + 배지 (❓조건 ⚡액션 🎬시퀀스) — 왼쪽 입력 포트 / 오른쪽 **next** 포트(파랑)
  - 본문 미리보기
  - 선택지 행들 — 오른쪽 **choice** 포트(노랑), 선택지당 1개

## 조작

| 작업 | 방법 |
|---|---|
| 노드 추가 | 캔버스 우클릭 → *Add Node Here* (또는 툴바 Add Node = 화면 중앙) |
| 연결 | 출력 포트(파랑=next, 노랑=choice)에서 대상 노드의 입력 포트로 드래그 — `next_node_id`/`target_node_id`가 갱신되고, 같은 포트에서 다시 드래그하면 교체 |
| 연결 해제 | 연결을 입력 포트에서 떼어내기(`right_disconnects`) |
| 노드 삭제 | 선택 후 Del 또는 툴바 Delete — **해당 노드를 가리키던 모든 링크 자동 정리** |
| 시작 노드 지정 | 노드 1개 선택 → Set Start |
| 필드 편집 | 노드 클릭 → **Inspector**에서 전체 필드 편집 (화자/텍스트/조건/액션/선택지/시퀀스) |
| 배치 저장 | 노드를 끌어 정리 → Save (위치는 노드 `metadata.graph_position`에 .tres로 저장) |
| 새 대화 | New Dialogue → id 입력 (start 노드 자동 생성) |

처음 여는 대화는 시작 노드 기준 BFS **자동 배치**됩니다(깊이=열, 분기=행).

## Inspector와의 관계

그래프와 Inspector는 **같은 리소스 인스턴스**를 편집합니다. Inspector에서 선택지를 추가/삭제하는 등 구조를 바꿨다면 **Refresh**(또는 탭 재진입)로 캔버스를 다시 그리세요 — 위치·연결은 데이터에서 재구성되므로 잃지 않습니다.

## 현재 한계 (0.2.0-dev)

- **undo/redo 없음** — 삭제·연결 변경은 즉시 데이터에 반영됩니다. 작업 전 Save로 체크포인트를 만들고, 잘못됐으면 저장 없이 Refresh가 아닌 **재로드 전이라면** 파일 재열기로 복구하세요. (Ctrl+Z 통합은 로드맵)
- 텍스트 인라인 편집 없음 — 필드는 Inspector 경유 (점진 도입 예정)
- 노드 id 변경(rename)은 Inspector에서 가능하지만 링크 문자열은 자동 추적되지 않음 — 변경 후 Validate로 끊어진 링크 확인

## 검증과의 연동

툴바 **Validate**는 요약(에러/경고 수)을 상태줄에 표시합니다 — 상세 목록은 하단 Narrative 패널의 Validation 탭에서 확인하세요.
