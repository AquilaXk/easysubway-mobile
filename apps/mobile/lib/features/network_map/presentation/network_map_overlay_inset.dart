import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 지도 본문 위쪽이 상단 오버레이(상단바·알림 바)에 가려지는 높이(dp).
///
/// 지도는 상단바 바로 아래에서 시작하지만 상단바는 입력 칸 수에 따라 1~3줄로
/// 커지고 알림 바까지 붙는다. 이 값은 그 오버레이의 측정 높이에서 나오므로
/// 카메라가 핀·팬 메뉴를 가려지지 않는 영역에 둘 수 있다. 오버레이가 없는 곳에서
/// 지도를 열면 가려지는 영역이 없으므로 0이다.
class NetworkMapObscuredTop extends InheritedWidget {
  const NetworkMapObscuredTop({
    required this.height,
    required super.child,
    super.key,
  });

  final double height;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NetworkMapObscuredTop>()
          ?.height ??
      0;

  @override
  bool updateShouldNotify(NetworkMapObscuredTop oldWidget) =>
      oldWidget.height != height;
}

/// 자식의 레이아웃 높이를 측정해, 바뀔 때마다 그 프레임이 끝난 뒤 [onHeight]로
/// 알린다. 상단바는 안쪽 위젯이 줄 수를 바꾸므로 build가 아니라 레이아웃 결과를
/// 읽어야 실제 높이를 놓치지 않는다.
class NetworkMapMeasuredHeight extends SingleChildRenderObjectWidget {
  const NetworkMapMeasuredHeight({
    required this.onHeight,
    required super.child,
    super.key,
  });

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderNetworkMapMeasuredHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderNetworkMapMeasuredHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class RenderNetworkMapMeasuredHeight extends RenderProxyBox {
  RenderNetworkMapMeasuredHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reportedHeight;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reportedHeight) {
      return;
    }
    _reportedHeight = height;
    // 레이아웃 중에는 setState를 부를 수 없으므로 프레임 뒤에 알린다.
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
