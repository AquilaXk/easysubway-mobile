<!-- B/C등급(일반 코드 변경·낮은 위험 maintenance) 전용. A등급(제품/운영 위험, CI/계약 테스트/release gate 변경)은 full.md를 사용합니다. -->

## 관련 이슈

<!-- umbrella `Refs #N` 또는 `이슈 없음(C등급)` 명기. 빈 칸 금지. -->

Refs #

## 작업 내용

-

## 검증

<!-- 예: apps/mobile에서 dart format --output=none --set-exit-if-changed lib test / flutter analyze / flutter test, tools/** 변경 시 node --test <대상> -->

- 실행한 명령과 결과:

## 영향

- [ ] 제품/운영 위험 없음 (route 결과 UI/accessibility/mobile UX/auth/security 아님)
- [ ] store 배포·서명 영향 없음
- [ ] datapack 소비·갱신 영향 없음
- [ ] contracts/mobile/** 계약 영향 없음
- [ ] CI workflow·계약 테스트·release gate JSON(apps/mobile/release/**) 변경 없음 (있으면 full.md로 전환)

## 체크리스트

- [ ] 이 PR은 B/C등급 작업이며 full template이 필요 없다.
- [ ] CI 결과를 확인했다.
- [ ] CodeRabbit 리뷰 결과와 필요한 조치를 확인하고 반영했다.
- [ ] GitHub PR Review 객체가 있는지 확인했다. CodeRabbit status check만으로는 리뷰 완료로 보지 않는다.
- [ ] CodeRabbit 실행이 불가능하거나 PR Review 객체가 없으면 폴백 리뷰를 단일 PR review로 게시했다.
