<!-- A등급: high-risk generated contract, state, UI/accessibility, privacy, artifact, release, CI·contract 변경. -->

## Related issue

Related #

## Summary

- Problem:
- Outcome:

## Changes

-

## Scope

### Included

-

### Excluded

-

### Ownership / dependencies

- Accountable owner or plan:
- Required predecessor output:
- Concurrent work overlap: None

## Contract & Compatibility

- Generated API / application-state contract:
- UI / accessibility behavior:
- Backward compatibility:
- Migration or release cutover:

## Version impact

- [ ] no version change
- [ ] mobile patch
- [ ] mobile minor
- [ ] mobile major
- [ ] store release only
- [ ] datapack 소비 변경
- [ ] contracts/mobile/** 계약 변경

## Release gate impact

- [ ] apps/mobile/release/*.json 영향 없음
- [ ] android release quality, accessibility QA, signed artifact, route result UI copy 근거를 갱신했습니다.
- [ ] 출시 준비 완료 claim을 추가하거나 변경하지 않습니다.

## Store submission readiness impact

- [ ] store-submission-readiness.json 영향 없음
- [ ] play production access, privacy inventory, 제출 콘텐츠 근거를 갱신했습니다.
- [ ] Google Play 출시 가능 claim을 추가하거나 변경하지 않습니다.

### Version decision

- mobile versionName / versionCode:
- datapack version:
- mobile contract / consumer snapshot:
- AAB identity:

## Verification

| Check | Result / Evidence |
| --- | --- |
| Focused RED → GREEN | |
| Affected integration | |
| Required CI | |
| UI / accessibility / device | Not required — reason: |
| Release / privacy / artifact | Not applicable — reason: |

## Not run

- Check: None
- Reason:
- Rerun owner / condition:

## Risk

- Level: High
- Main risk:
- Failure behavior:
- User-visible / state / release mutation on failure:
- Fallback or degraded-success path introduced: No

## Rollout / Recovery

- Rollout or release:
- Monitoring / success signal:
- Rollback or recovery:
- State / generated contract / data compatibility after rollback:

## Review focus

-

## Checklist

- [ ] 이슈 범위와 실제 diff가 일치합니다.
- [ ] 관련 없는 변경이나 다른 owner의 surface를 포함하지 않았습니다.
- [ ] 위험에 필요한 검증과 미실행 사유를 기록했습니다.
- [ ] 실패·호환성·release·recovery 동작이 명확합니다.
- [ ] current failure를 previous/local/legacy 결과의 성공 표시로 바꾸지 않습니다.
- [ ] CodeRabbit 리뷰 결과와 필요한 조치를 확인했습니다.
- [ ] GitHub PR Review 객체가 있는지 확인했습니다. CodeRabbit status check만으로는 리뷰 완료로 보지 않습니다.
- [ ] CodeRabbit Review 객체가 없으면 지원되는 Codex CLI 폴백 Review를 단일 GitHub PR Review로 게시했습니다.
- [ ] store 배포 영향이 있는 경우 release·distribution workflow 상태를 확인했습니다.
