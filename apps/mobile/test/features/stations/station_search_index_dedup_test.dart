import 'package:easysubway_mobile/features/stations/data/station_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StationSearchIndex single-pass deduplication', () {
    test(
      'collectNamePrefixInto와 lookupNamePrefix가 단일 패스로 중복 stationId를 제거한다',
      () {
        final index = StationSearchIndex.build(const [
          StationSearchIndexStationRow(
            stationId: 'st-gangnam',
            koreanTerms: ['강남', '강남역'],
            englishTerms: ['gangnam'],
            subnameTerms: ['gangnam-sub', '강남구청근처'],
            chosungTerms: ['ㄱㄴ'],
          ),
          StationSearchIndexStationRow(
            stationId: 'st-gangbyeon',
            koreanTerms: ['강변'],
            englishTerms: ['gangbyeon'],
            subnameTerms: ['동서울터미널'],
            chosungTerms: ['ㄱㅂ'],
          ),
        ]);

        final into = <String>{};
        index.collectNamePrefixInto('gangnam', into);
        expect(into, {'st-gangnam'});
        expect(index.lookupNamePrefix('gangnam'), {'st-gangnam'});

        final chosungInto = <String>{'st-gangnam'};
        index.collectChosungPrefixInto('ㄱ', chosungInto);
        expect(chosungInto, {'st-gangnam', 'st-gangbyeon'});

        final overlapInto = <String>{};
        index.collectNamePrefixInto('강', overlapInto);
        expect(overlapInto, {'st-gangnam', 'st-gangbyeon'});
      },
    );
  });
}
