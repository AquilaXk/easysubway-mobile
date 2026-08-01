<!--
작업 등급에 맞는 템플릿을 사용하세요.
- A등급(제품/운영 위험: route 결과 UI, accessibility, mobile UX, datapack 소비·갱신, store 배포·서명, auth, security, CI workflow·계약 테스트(contracts/mobile/**)·release gate JSON(apps/mobile/release/**) 변경): .github/PULL_REQUEST_TEMPLATE/full.md 내용으로 교체합니다.
- B/C등급(일반 코드 변경·낮은 위험 maintenance): .github/PULL_REQUEST_TEMPLATE/short.md 내용으로 교체합니다(아래 기본형과 동일).
- 웹 UI에서는 ?template=full.md 또는 ?template=short.md 쿼리를 쓸 수 있습니다. gh CLI는 template 쿼리를 지원하지 않으므로 템플릿 파일 내용을 body로 직접 채웁니다.
- 리뷰·automerge 게이트는 등급과 무관하게 모든 PR 공통입니다.
-->

## 관련 이슈

<!-- 단일 PR은 `Closes #N`, 스택 중간/umbrella는 `Refs #N`, C등급 issue 생략 시 `이슈 없음(C등급)` 명기. 빈 칸 금지. -->

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

- [ ] 작업 등급에 맞는 템플릿을 사용했다.
- [ ] CI 결과를 확인했다.
- [ ] GitHub PR Review 객체가 있는지 확인했다. CodeRabbit status check만으로는 리뷰 완료로 보지 않는다.
- [ ] CodeRabbit 실행이 불가능하거나 PR Review 객체가 없으면 폴백 리뷰를 단일 PR review로 게시했다.
