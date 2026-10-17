import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 다국어는 지원하지 않으므로 모든 `MaterialApp` 루트는 한국어 하나로 고정해
/// 기본 위젯의 툴팁·낭독 라벨을 앱 UI 언어와 일치시킨다.
const appLocale = Locale('ko', 'KR');
const appSupportedLocales = [appLocale];
const appLocalizationsDelegates = GlobalMaterialLocalizations.delegates;
