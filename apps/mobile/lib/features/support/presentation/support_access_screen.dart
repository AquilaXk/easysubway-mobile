import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../support_access.dart';

class UrlLauncherSupportAccessLauncher implements SupportAccessLauncher {
  const UrlLauncherSupportAccessLauncher();

  @override
  Future<bool> open(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class SupportAccessScreen extends StatelessWidget {
  const SupportAccessScreen({
    required this.accessInfo,
    required this.launcher,
    required this.userDataDeletionAccessItem,
    super.key,
  });

  final SupportAccessInfo accessInfo;
  final SupportAccessLauncher launcher;
  final Widget? userDataDeletionAccessItem;

  @override
  Widget build(BuildContext context) {
    final deletionChildren = <Widget>[
      if (userDataDeletionAccessItem != null)
        userDataDeletionAccessItem!
      else if (buildSupportMailtoUri(
            email: accessInfo.dataDeletionEmail,
            subject: '쉬운 지하철 내 정보 삭제 요청',
          ) !=
          null)
        _SupportAccessItem(
          key: const Key('dataDeletionAccessItem'),
          title: '내 정보 삭제 요청',
          value: accessInfo.dataDeletionEmail,
          displayValue: '이메일 보내기',
          uri: buildSupportMailtoUri(
            email: accessInfo.dataDeletionEmail,
            subject: '쉬운 지하철 내 정보 삭제 요청',
          ),
          launcher: launcher,
        ),
    ];

    return Scaffold(
      key: const Key('supportAccessScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('supportAccessAppBar'),
        title: const Text('도움말'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('supportAccessBackButton'),
          tooltip: '뒤로',
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(EasySubwayTouchTarget.general),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(
            Icons.arrow_back,
            size: 26,
            color: EasySubwayAccessibleColors.contentPrimary,
          ),
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(
            key: Key('supportAccessHeaderDivider'),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (deletionChildren.isNotEmpty)
              _SupportSettingsSection(
                key: const Key('supportSection-privacy'),
                title: '내 정보와 개인정보',
                children: deletionChildren,
              ),
            _SupportSettingsSection(
              key: const Key('supportSection-safety'),
              title: '이동 전 살펴보기',
              children: const [_SafetyDataNotice()],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportSettingsSection extends StatelessWidget {
  const _SupportSettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColoredBox(
          key: Key('supportSectionHeader-$title'),
          color: EasySubwayAccessibleColors.scaffoldSurface,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.secondaryText,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ),
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 20,
              endIndent: 20,
              color: EasySubwayAccessibleColors.line,
            ),
        ],
      ],
    );
  }
}

class _SafetyDataNotice extends StatelessWidget {
  const _SafetyDataNotice();

  static const _title = '이동 전 살펴보기';
  static const _referenceNotice = '경로와 시설 정보는 이동을 돕는 참고 정보입니다.';
  static const _fieldNotice = '실제 이동 전에는 현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요.';
  static const _limitationNotice = '실시간 상태나 무조건 안전한 경로를 보장하지 않습니다.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('safetyDataNotice'),
      container: true,
      label: '$_title, $_referenceNotice $_fieldNotice $_limitationNotice',
      child: ExcludeSemantics(
        child: ColoredBox(
          color: EasySubwayAccessibleColors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SupportNoticeBullet(text: _referenceNotice),
                const SizedBox(height: 10),
                const _SupportNoticeBullet(text: _fieldNotice),
                const SizedBox(height: 10),
                const _SupportNoticeBullet(text: _limitationNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportNoticeBullet extends StatelessWidget {
  const _SupportNoticeBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: EasySubwayAccessibleColors.secondaryText,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _SupportAccessItem extends StatelessWidget {
  const _SupportAccessItem({
    required this.title,
    required this.value,
    required this.uri,
    required this.launcher,
    this.displayValue,
    super.key,
  });

  final String title;
  final String value;
  final Uri? uri;
  final SupportAccessLauncher launcher;
  final String? displayValue;

  @override
  Widget build(BuildContext context) {
    final targetUri = uri;
    final targetText = value.trim();
    final displayValue = this.displayValue ?? targetText;
    final semanticLabelParts = [title, displayValue];
    if (targetUri != null && displayValue != targetText) {
      semanticLabelParts.add(targetText);
    }
    final onTap = targetUri == null
        ? null
        : () => unawaited(_openTarget(context, targetUri, targetText));
    return Semantics(
      button: true,
      container: true,
      enabled: targetUri != null,
      label: semanticLabelParts.join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        child: ListTile(
          onTap: onTap,
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          tileColor: EasySubwayAccessibleColors.surface,
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          subtitle: Text(
            displayValue,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.mutedText,
              height: 1.3,
            ),
          ),
          trailing: targetUri == null
              ? null
              : const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.disclosure,
                ),
        ),
      ),
    );
  }

  Future<void> _openTarget(
    BuildContext context,
    Uri uri,
    String targetText,
  ) async {
    bool opened = false;
    try {
      opened = await launcher.open(uri);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '도움말 외부 연결 실행 중 예외가 발생했습니다.',
      );
    }

    if (!context.mounted || opened) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('연결할 수 없습니다. 직접 확인해 주세요: $targetText')),
    );
  }
}
