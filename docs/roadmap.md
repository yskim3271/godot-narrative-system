# 로드맵

## M2 — 저작 경험 (다음 마일스톤)

1. **GraphEdit 기반 대화 그래프 에디터** (보기/노드 추가/연결/시작 노드 지정 → 점진적으로 인라인 편집) — 검증기·리소스 모델은 이미 그래프 친화적으로 설계됨
2. 하단 패널 고도화: 대화 미리보기(에디터 내 재생), 누락 번역 일괄 표시, 검증 이슈 더블클릭 → 해당 리소스 포커스
3. 텍스트 저작 포맷(.ndlg) 파서 — `dialogue_script_parser.gd` (작가 친화 워크플로)
4. 인라인 마크업: `[var=x]`, `[color]` 헬퍼, 자동 넘버링 단축키

## M3 — 런타임 고도화

1. 시퀀서 `@time` 병렬 스케줄링 + `->message` 동기화 (Unity DS 패리티), Camera3D/3D bark 지원
2. 퀘스트: abandon/반복 퀘스트, objective 자동 완료 조건, 카테고리
3. 대화 인터럽트 스택(컷인), 동시 bark 다중화 정책
4. 저장 슬롯 메타데이터 API(스크린샷/플레이타임), `SaveServer` 제안 추이 반영

## M4 — 생태계 연동/배포

1. Yarn Spinner / Ink 임포터 (NarrativeDatabase로 변환)
2. CSV로 대화 본문 왕복(현재는 로컬라이징 테이블만)
3. C# 우선 API 래퍼 + 예제
4. 데모 4분할(basic/quest/localization/cutscene) + Godot Asset Library 패키징(버전 태그, export-ignore)

## 항시 항목

- Godot 마이너 업데이트 호환성 확인(테스트 파이프라인 재실행)
- `docs/research/phase0_research.md`의 경쟁 플러그인 동향 갱신
