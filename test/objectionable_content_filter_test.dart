import 'package:eleaguehub3/core/moderation/objectionable_content_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObjectionableContentFilter blocks', () {
    final blocked = <String>[
      'what the fuck was that',
      'FUCK',
      'you absolute sh1t',
      'b!tch please',
      'fuuuuck this ref',
      'f u c k off',
      'what an asshole',
      'go kill yourself',
      'kill urself',
      'kys',
      'nigger',
      'send nudes',
      'he is a faggot',
    ];
    for (final text in blocked) {
      test('"$text"', () {
        expect(ObjectionableContentFilter.isAllowed(text), isFalse);
        expect(
          () => ObjectionableContentFilter.ensureAllowed(text),
          throwsA(isA<ObjectionableContentException>()),
        );
      });
    }
  });

  group('ObjectionableContentFilter allows ordinary football talk', () {
    final allowed = <String>[
      '',
      '   ',
      'Great match today! 3-1 win',
      'Niger vs Nigeria friendly this Saturday',
      'Dick Advocaat named new coach',
      'That was a chink in their armour',
      'Scunthorpe United are top of the league',
      'Classic counter attack, he will shoot on sight',
      'You need to improve your skill yourself',
      'We will kill the game in the second half',
      'Assist of the season',
      'Bass player Cocky striker Cockerill',
      'Coach said: grass was wet',
      'Van Dijk wins the duel',
      'الفريق لعب بشكل رائع',
      'Goal!!!',
      r'$100 prize pool for the tournament',
    ];
    for (final text in allowed) {
      test('"$text"', () {
        expect(ObjectionableContentFilter.findViolation(text), isNull);
        ObjectionableContentFilter.ensureAllowed(text);
      });
    }
  });

  test('exception carries a user-facing message', () {
    const e = ObjectionableContentException();
    expect(e.message, contains("isn't allowed"));
    expect(e.toString(), e.message);
  });
}
