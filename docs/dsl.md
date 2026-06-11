# 조건/액션 DSL 사양

대화 노드의 `conditions`, `actions`, 선택지의 `condition`/`actions`, 퀘스트 `rewards`, 시퀀서 명령은 모두 **하나의 안전한 미니 언어**로 작성한다. GDScript eval이나 Godot `Expression` 클래스를 사용하지 않으며(임의 코드 실행 차단), 자체 토크나이저+재귀하강 파서로 구현된다.

## 1. 진입점 3개

| 진입점 | 입력 | 결과 |
|---|---|---|
| 조건식 (condition) | 표현식 1개 (빈 문자열 = `true`) | `bool` (bool 아니면 에러→false) |
| 액션 (actions) | 문장 목록 (`;` 또는 개행 구분) | 부수효과 (변수 대입, 함수 호출) |
| 시퀀서 (sequence) | 함수 호출 목록만 | 명령 큐 |

## 2. 토큰

- `IDENT`: `[A-Za-z_][A-Za-z0-9_.]*` — 점은 이름 중간에만 (`player.gold` 허용, 멤버 접근 아님·통짜 이름임). 키워드 `and or not true false null` 제외
- `NUMBER`: `123` (int) / `1.5` (float). 지수·선행 점 없음
- `STRING`: `"..."` 또는 `'...'`, 이스케이프 `\\ \" \' \n \t`
- 연산자: `== != <= >= < > + - * / % = += -= ->` (최대 일치: `==`/`->` 우선. `->`는 시퀀서 줄 장식 전용)
- 구두점: `( ) , ; @` (`@`는 시퀀서 줄 장식 전용) · 주석: `#`~행끝 · `NEWLINE`: 액션/시퀀서 모드에서만 문장 구분자

## 3. 문법 (EBNF)

```ebnf
condition   = [ expr ] , EOF ;
actions     = [ stmt { separator stmt } ] , EOF ;   separator = ";" | NEWLINE ;
stmt        = assignment | call ;                    (* 시퀀서 모드: seq_line만 *)
seq_line    = call [ "@" ( NUMBER | "message" "(" STRING ")" ) ]
                   [ "->" ( STRING | "message" "(" STRING ")" ) ] ;  (* 시퀀서 전용, sequencer.md *)
assignment  = IDENT ( "=" | "+=" | "-=" ) expr ;     (* 조건 모드에서 불법 → 파스 에러 *)
call        = IDENT "(" [ expr { "," expr } ] ")" ;
expr        = or_expr ;
or_expr     = and_expr { "or" and_expr } ;
and_expr    = not_expr { "and" not_expr } ;
not_expr    = "not" not_expr | comparison ;
comparison  = additive [ ("=="|"!="|"<"|"<="|">"|">=") additive ] ;  (* 비결합: a<b<c 파스 에러 *)
additive    = multiplicative { ("+"|"-") multiplicative } ;
multiplicative = unary { ("*"|"/"|"%") unary } ;
unary       = "-" unary | primary ;
primary     = NUMBER | STRING | "true" | "false" | "null" | call | IDENT | "(" expr ")" ;
```

우선순위(낮→높): `or` < `and` < `not` < 비교(비결합) < `+ -` < `* / %` < 단항 `-` < primary.

설계 의도: 조건에 대입이 없으므로 `=`/`==` 오타는 **파스 에러**로 즉시 드러난다. 비교 연쇄 금지, 암묵적 truthiness 금지(조건 결과는 반드시 bool).

## 4. 평가 의미론

값 도메인: `null | bool | int | float | String`.

| 연산 | 규칙 |
|---|---|
| `+` | int+int→int, 숫자 혼합→float, String+String→연결. **그 외 조합은 에러** (`str(x)` 내장 사용) |
| `- *` | 숫자만. int·int→int, 그 외 float |
| `/` | 숫자만, **항상 float**. `/0` 에러 |
| `%` | int%int만. `%0` 에러 |
| `== !=` | 숫자끼리는 값 비교(3 == 3.0). 타입 불일치는 **에러 없이 false**. `null==null`은 true |
| `< <= > >=` | 둘 다 숫자 또는 둘 다 String(사전순). 그 외 에러 |
| `and or not` | 피연산자 bool 필수, 좌→우 단락 평가 |
| 변수 읽기 | 미지 변수 → 경고+`null` |
| 대입 | 미선언 변수 대입 → 임시 변수 생성+경고. 선언 변수는 선언 타입으로 숫자 강제 변환, 호환 불가 타입은 경고+문장 스킵 |
| 함수 호출 | 인자 좌→우 평가. 미지 함수 → 에러 |

**에러 정책**: 파스/평가에 실패한 조건은 `false`+경고(소스·위치별 세션당 1회 — 루프 스팸 방지). 실패한 액션 **문장**은 스킵+경고 후 나머지 문장 계속 실행(문장은 서로 독립). 같은 소스 문자열은 파스 1회 후 캐시.

## 5. 내장 함수

`str(x)` · `has_seen(dialogue_id[, node_id])` · `quest_state(id)→String` · `is_quest_active(id)` · `is_quest_completed(id)` · `is_quest_failed(id)` · `start_quest(id)` · `complete_quest(id)` · `fail_quest(id)` · `abandon_quest(id)` · `times_completed(id)→int` · `update_objective(quest_id, objective_id, delta=1)` · `objective_count(quest_id, objective_id)→int` · `set_expression(character_id, expression)` · `alert(text_or_key)`

## 6. 게임 함수 등록

```gdscript
Narrative.register_function("has_item", func(item_id: String) -> bool:
    return Inventory.has(item_id))
```
- 내장/기존 이름과 충돌 시 거부(`override = true`로 명시 교체)
- 반환값은 값 도메인 내여야 함
- 에디터 Validator는 게임 등록 함수를 알 수 없으므로, 설정의 "declared external functions" 목록에 이름을 적으면 미지 함수 호출을 에러 대신 경고로 다운그레이드

## 7. 예시

```text
# 조건
met_guard and player.gold >= 100 and not is_quest_active("find_sword")
has_seen("guard_intro") or quest_state("find_sword") == "completed"

# 액션
player.gold -= 100; met_guard = true
start_quest("find_sword")
alert("ui.alert.quest_started")

# 시퀀서
wait(0.5)
set_expression("guard", "angry")
play_animation("guard", "wave")
```
