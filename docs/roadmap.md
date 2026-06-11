# 로드맵

## M2 — 저작 경험

1. ~~GraphEdit 기반 대화 그래프 에디터~~ ✅ — ~~구조 변경 undo/redo~~ ✅ 1.0.0 · ~~텍스트/화자 인라인 편집~~ ✅ · ~~노드 id rename 시 링크 자동 추적~~ ✅ · ~~선택지 텍스트/타깃 인라인 편집~~ ✅
2. 하단 패널 고도화: 대화 미리보기(에디터 내 재생), 누락 번역 일괄 표시, 검증 이슈 더블클릭 → 해당 리소스 포커스
3. ~~텍스트 저작 포맷(.ndlg) 파서~~ ✅ 1.0.0 (`dialogue_script_parser.gd`, 원자적 임포트+왕복 익스포트, 패널 버튼)
4. ~~인라인 마크업~~ ✅ — `[var=x]` 런타임 치환(대사/선택지/바크/알림) + 검증기 경고, 에디터 삽입 단축키(Ctrl+Shift+V/C), 선택지 자동 넘버링(1.2.3 버튼/Ctrl+Shift+N)

## M3 — 런타임 고도화

1. ~~시퀀서 `@time` 병렬 스케줄링 + `->message`/`@message` 동기화 (Unity DS 패리티), `move_camera_3d`·3D `focus_camera`·3D bark~~ ✅
2. 퀘스트: abandon/반복 퀘스트, objective 자동 완료 조건, 카테고리
3. 대화 인터럽트 스택(컷인), 동시 bark 다중화 정책
4. 저장 슬롯 메타데이터 API(스크린샷/플레이타임), `SaveServer` 제안 추이 반영

## M4 — 생태계 연동/배포

1. Yarn Spinner / Ink 임포터 (NarrativeDatabase로 변환)
2. CSV로 대화 본문 왕복(현재는 로컬라이징 테이블만)
3. C# 우선 API 래퍼 + 예제
4. ~~데모 4분할(basic/quest/localization/cutscene)~~ ✅ 1.0.0 — 잔여: Godot Asset Library 패키징(버전 태그, export-ignore)

## 항시 항목

- Godot 마이너 업데이트 호환성 확인(테스트 파이프라인 재실행)
- `docs/research/phase0_research.md`의 경쟁 플러그인 동향 갱신
