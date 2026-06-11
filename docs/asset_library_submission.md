# Godot Asset Library 제출 가이드 / 체크리스트

Asset Library는 **공개 git 저장소의 특정 커밋/태그 zip**을 그대로 서빙합니다. 이 저장소는 `.gitattributes`의 `export-ignore`로 패키지를 **`addons/narrative_system/`만** 남기도록 구성되어 있습니다(데모 프로젝트·docs·테스트·`project.godot`·루트 README 등은 저장소 전용 — 사용자의 프로젝트 파일을 덮어쓰지 않음).

## 패키지 내용물 (v1.2.0 기준)

`git archive` 결과 = 사용자가 설치 시 받는 것:

```
addons/narrative_system/
  README.md            ← 영문 패키지 README
  LICENSE              ← MIT
  plugin.cfg           ← version = 버전 태그와 일치해야 함
  plugin.gd, version.gd
  runtime/ resources/ ui/ editor/ validation/ import_export/
  (tests/ 제외 — export-ignore)
```

확인 명령(제출 전 필수):

```powershell
git archive v1.2.0 -o package_check.zip
# zip 내용이 addons/narrative_system/** 뿐인지, tests/가 없는지 확인 후 삭제
# (v1.2.0 검수 완료: 117 엔트리, tests/docs/examples/project.godot 제외 확인)
```

## 릴리스 절차 (버전마다)

1. `CHANGELOG.md`의 Unreleased를 버전 절로 확정.
2. **버전 3곳 동기화**: `addons/narrative_system/plugin.cfg`의 `version`, `addons/narrative_system/version.gd`의 `VERSION`, git 태그 `vX.Y.Z`. (저장 스키마가 바뀐 경우에만 `SAVE_VERSION` + 마이그레이션 — [save_format.md](save_format.md).)
3. `.\scripts\run_tests.ps1` ALL GREEN 확인 → 커밋 → `git tag vX.Y.Z`.
4. `git archive vX.Y.Z`로 패키지 내용 검수(위 명령).
5. **신규 설치 스모크 테스트**: 빈 Godot 4.4+ 프로젝트에 zip의 `addons/`를 풀고 플러그인 활성화 → 에러 0, `Narrative` autoload 등록, 하단 Narrative 패널·메인스크린 Narrative 탭 표시 확인.
6. 공개 저장소(GitHub 등)에 push + 태그 push: `git push origin main --tags`.
7. Asset Library 제출/업데이트 (아래 양식 값).

## 제출 양식 값

| 필드 | 값 |
|---|---|
| Asset name | Narrative System for Godot |
| Category | `Tools` (또는 `Scripts` — 에디터 도구+런타임 혼합은 Tools 권장) |
| License | MIT |
| Godot version | 4.4 (이상에서 동작, 4.6.3에서 개발·검증) |
| Version string | `1.2.0` — plugin.cfg와 반드시 일치 |
| Repository host / URL | GitHub / `https://github.com/yskim3271/godot-narrative-system` (main + v1.0.0/v1.1.0/v1.2.0 태그 push 완료) |
| Issues URL | `https://github.com/yskim3271/godot-narrative-system/issues` |
| Download Commit | `04074dfe217eac7103fd7a1a65d3696570a9f279` (= `git rev-parse v1.2.0`) |
| Icon URL | `https://raw.githubusercontent.com/yskim3271/godot-narrative-system/main/icon.png` (icon.svg에서 256×256 PNG 생성 — `scripts/make_icon.gd`) |
| Description | 영문 — `addons/narrative_system/README.md`의 첫 단락 + Features 요약 사용 |
| Preview images | docs/screenshots/ 캡처 완료 — raw URL: `https://raw.githubusercontent.com/yskim3271/godot-narrative-system/main/docs/screenshots/` + `graph_editor.png` / `preview_panel.png` / `demo_dialogue_choices.png` / `demo_quest_log.png` / `demo_quest_start.png` |

## 심사 통과 요건 점검 (제출 전 최종)

- [ ] 저장소가 공개이고 태그가 push되어 있다
- [ ] zip이 `addons/<plugin>/` 구조로 풀린다 (위 archive 검수)
- [ ] `plugin.cfg`의 `version` == 제출 Version string == 태그
- [ ] LICENSE가 패키지 안에 있다 (`addons/narrative_system/LICENSE`)
- [ ] 영문 README가 패키지 안에 있다 (`addons/narrative_system/README.md`)
- [ ] 빈 프로젝트 신규 설치 스모크 테스트 통과 (5번)
- [ ] 데모/스크린샷 URL이 유효하다

## 메모

- AssetLib 다운로드는 저장소 zip이므로 **저장소 전용 파일을 추가할 때마다** `.gitattributes`의 export-ignore 목록을 함께 검토할 것 (루트에 새 파일/폴더를 만들면 기본적으로 패키지에 포함된다).
- 데모를 패키지에 포함하지 않는 것은 의도적 결정 — 데모 5종은 저장소를 클론해서 실행 (`README.md`/애드온 README에 안내됨).
