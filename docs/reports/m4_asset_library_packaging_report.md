# M4-4. Godot Asset Library 배포 패키징 (1.1.0)

## 목표
Asset Library 제출 가능 상태로 패키징: 배포 zip을 애드온만으로 구성(export-ignore), 영문 패키지 README, 제출 체크리스트 문서, 버전 태그.

## 구현 내용
- **`.gitattributes` export-ignore**: `git archive`(= AssetLib가 서빙하는 저장소 zip)가 **`addons/narrative_system/`만** 담도록 구성 — docs/examples/scripts/tests, `project.godot`, 루트 README·CHANGELOG·LICENSE·icon 등 프로젝트 레벨 파일 전부 제외(설치가 사용자 프로젝트 파일을 덮어쓰지 않도록). 애드온 내부의 README/LICENSE는 패키지에 포함.
- **영문 패키지 README** (`addons/narrative_system/README.md`): 기존 한국어 스텁 → 기능 요약(그래프 에디터·.ndlg·마크업·시퀀서 병렬·3D·저장·로컬라이징·검증기)·설치·퀵스타트·문서 안내를 담은 영문 README로 교체. 루트(한국어) README에 영문 README 포인터 추가, 테스트 수 갱신(137→212).
- **제출 체크리스트** (`docs/asset_library_submission.md`): 패키지 내용물 검수 명령(`git archive vX.Y.Z`), 릴리스 절차(버전 3곳 동기화 — plugin.cfg/version.gd/태그), 제출 양식 값(카테고리/버전/커밋 해시/아이콘), 심사 요건 점검 목록, 신규 설치 스모크 테스트 절차. **공개 저장소가 아직 없음**(로컬 전용)을 명시 — push 후 URL 기입.
- **버전 1.1.0**: plugin.cfg·version.gd 범프(SAVE_VERSION은 1 유지 — 저장 스키마 무변경), CHANGELOG Unreleased → 1.1.0 확정(이번 세션의 M2 완결·마크업·시퀀서 병렬·3D 항목 포함), `v1.1.0` 태그.

## 발견된 문제
없음.

## 생성/수정 파일
.gitattributes, addons/narrative_system/README.md(영문화)·plugin.cfg·version.gd, README.md, CHANGELOG.md, docs/asset_library_submission.md(신규)·roadmap.md.

## 검증 방법 / 테스트 결과
- 전체 파이프라인 **ALL GREEN**: 유닛 **212/212** · 해피패스 클린 · 데모 DB strict 0/0 · 데모 5종 부팅 OK.
- **패키지 검수**: `git archive --worktree-attributes` zip = 111 엔트리, 최상위 `addons/`뿐, tests/ 0개, 애드온 README+LICENSE 포함 확인.
- 버전 동기화: plugin.cfg `1.1.0` == version.gd `1.1.0` == 태그 `v1.1.0`.

## 남은 한계 / 후속
- 실제 제출은 **공개 저장소 push가 선행**되어야 함(현재 remote 없음) — 절차는 asset_library_submission.md에 정리. 아이콘은 SVG 보유, AssetLib 권장 PNG(256×256)는 제출 시 생성.

## 다음 단계
로드맵 잔여: M2-2(하단 패널 고도화), M3-2~4(퀘스트 반복/abandon, 인터럽트 스택, 저장 슬롯 메타), M4-1~3(Yarn/Ink 임포터, 대화 본문 CSV, C# 래퍼).
