# 로컬라이징

애드온 자체 테이블(`NarrativeLocalizationTable`)을 사용합니다 — 프로젝트 수준 CSV 임포트에 의존하지 않으므로 데이터베이스가 번역을 **함께 들고 다니고**, 런타임 언어 전환·누락 키 수집이 가능합니다.

## 텍스트 해석 순서

모든 대사/선택지/퀘스트 텍스트는 다음 순서로 결정됩니다:

1. **명시 키** (`localized_text_key` 등) — 현재 언어
2. **관례 키** — 현재 언어
3. **인라인 텍스트** — 리소스에 적힌 원문 = **기본 언어**
4. 명시 키 — 폴백 언어 (인라인이 없는 키 전용 콘텐츠일 때만 도달)
5. 관례 키 — 폴백 언어

핵심: **번역이 비어 있으면 폴백 "언어"가 아니라 저작 원문이 보입니다.** (ko로 쓰고 en만 번역한 DB에서 ko 유저가 영어를 보는 사고 방지)

## 관례 키 (자동 인식 — 키를 일일이 지정할 필요 없음)

| 대상 | 키 |
|---|---|
| 노드 대사 | `dlg.{dialogue_id}.{node_id}.text` |
| 선택지 | `dlg.{dialogue_id}.{node_id}.choice.{choice_id}` |
| 캐릭터 이름 | `char.{id}.name` |
| 퀘스트 제목/설명 | `quest.{id}.title` / `quest.{id}.desc` |
| objective | `quest.{quest_id}.obj.{objective_id}` |
| 기본 UI 문구 | `ui.quest_log.title`, `ui.quest_log.active` … (코드 폴백 내장) |

권장 워크플로: **원문은 인라인으로 저작** → 번역가는 관례 키 CSV만 채움. (데모가 정확히 이 구조: ko 인라인 + en 테이블)

누락 점검: 하단 **Narrative 패널 → Localization 탭**이 위 해석 순서 그대로 전 번역 단위의 커버리지를 계산해 로케일별 누락 목록을 보여줍니다(기본 언어는 인라인 텍스트로 커버 처리). 행 더블클릭 = 해당 리소스 포커스.

## CSV 왕복

- 형식: 헤더 `key,en,ko,...` — Excel이 붙이는 UTF-8 BOM은 자동 제거, 빈 셀은 기존 번역을 지우지 않음
- 에디터: 하단 **Narrative 패널 → Export CSV / Import CSV** (임포트 후 .tres 자동 저장)
- 코드/CI:
  ```gdscript
  const CsvExporter := preload("res://addons/narrative_system/import_export/csv_exporter.gd")
  const CsvImporter := preload("res://addons/narrative_system/import_export/csv_importer.gd")
  CsvExporter.export_table(db.localization_tables[0], "res://loc/strings.csv")
  CsvImporter.import_into(db.localization_tables[0], "res://loc/strings.csv")
  ```

## 언어 전환과 알림/바크

```gdscript
Narrative.set_language("en")    # 표시 중인 대사·선택지·퀘스트 UI 즉시 재표시
Narrative.get_language()
```
`show_alert()`/`bark()`의 인자는 **키이거나 평문**이어도 됩니다 — 테이블에 있는 키면 번역되고, 아니면 그대로 표시됩니다.

설정(`NarrativeSettings`): `default_language`, `fallback_language`, `collect_missing_keys`, `sync_godot_locale`(켜면 `TranslationServer.set_locale`도 동기화 — 엔진 `tr()` 문자열과 함께 전환).

## 누락 키 점검

- 런타임: `Narrative.context.localization.missing_keys()` — 실제 플레이 중 해석 실패한 명시 키 목록
- 정적: 검증기(`Validate`)가 명시 키 중 어떤 언어에도 없는 키를 경고

## 한글 폰트

Godot 4.2+는 누락 글리프에 **시스템 폰트 폴백**을 기본 지원합니다 — Windows(맑은 고딕)/macOS에서는 별도 설정 없이 한글이 표시됩니다. 배포 시 모든 플랫폼에서 동일한 렌더링이 필요하면 Noto Sans KR 같은 폰트를 프로젝트 테마의 기본 폰트로 지정하세요(UI 씬들은 테마를 그대로 따릅니다).
