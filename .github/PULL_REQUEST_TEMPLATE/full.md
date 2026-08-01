## 관련 이슈

close #

## 작업 배경

-

## 작업 내용

-

## 검증

<!-- 예: apps/mobile에서 dart format --output=none --set-exit-if-changed lib test / flutter analyze / flutter test, tools/** 변경 시 node --test <대상> -->

- 실행한 명령과 결과:

## 검증 증거

UI, 접근성, 수동 QA, store 제출 확인이 필요한 항목은 증거 첨부, 링크, 또는 로컬 evidence 경로를 적습니다. 증거가 필요 없는 항목은 사유를 적습니다.

| 항목 | 플랫폼 | 확인 방법 | 증거 | 결과 |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

## Version impact

- [ ] no version change
- [ ] mobile patch
- [ ] mobile minor
- [ ] mobile major
- [ ] store release only
- [ ] datapack 소비 변경 (apps/mobile/assets/datapacks/**)
- [ ] contracts/mobile/** 계약 변경

## Release gate impact

- [ ] apps/mobile/release/*.json 영향 없음
- [ ] android release quality, accessibility release QA, signed release artifact, route result UI copy 게이트 보고를 갱신했다.
- [ ] 출시 준비 완료 claim을 추가하거나 변경하지 않는다.

## Store submission readiness impact

- [ ] store-submission-readiness.json 영향 없음
- [ ] play production access, store privacy inventory, store 제출 콘텐츠 근거를 갱신했다.
- [ ] Google Play 출시 가능 claim을 추가하거나 변경하지 않는다.

### Version decision

- mobile versionName:
- mobile versionCode:
- datapack version:
- mobile contract (contracts/mobile):
- consumer snapshot (consumer-snapshots.sha256):
- AAB identity:

## 리뷰어 메모

- 리뷰어가 먼저 봐야 할 지점:

## 리스크

-

## 체크리스트

- [ ] PR 본문은 이 템플릿 섹션을 삭제하지 않고 모두 채웠다.
- [ ] CI 결과를 확인했다.
- [ ] CodeRabbit 리뷰를 확인했다.
- [ ] GitHub PR Review 객체가 있는지 확인했다. CodeRabbit status check만으로는 리뷰 완료로 보지 않는다.
- [ ] CodeRabbit 실행이 불가능하거나 PR Review 객체가 없으면 폴백 리뷰를 단일 PR review로 게시했다.
- [ ] store 배포 영향이 있는 경우 release·distribution 워크플로 상태를 확인했다.
