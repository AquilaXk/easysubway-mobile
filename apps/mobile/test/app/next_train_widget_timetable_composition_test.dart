import 'package:easysubway_mobile/app/next_train_widget_timetable_composition.dart';
import 'package:easysubway_mobile/features/journey/data/journey_method_channel_integrity_attestor.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headless widget composition은 API base URI 부재를 즉시 실패로 표현한다', () {
    expect(
      () =>
          createNextTrainWidgetTimetableRepository(resolveBaseUri: () => null),
      throwsA(isA<StateError>()),
    );
  });

  test('headless widget composition은 주입한 Journey 경계만 조립한다', () {
    var attestors = 0;
    final repository = createNextTrainWidgetTimetableRepository(
      resolveBaseUri: () => Uri.parse('https://journey.example.test'),
      createAttestor: () {
        attestors += 1;
        return JourneyMethodChannelIntegrityAttestor();
      },
    );

    expect(repository, isA<ServerStationTimetableRepository>());
    expect(attestors, 1);
  });
}
