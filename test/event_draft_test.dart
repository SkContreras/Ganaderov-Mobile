import 'package:flutter_test/flutter_test.dart';
import 'package:ganaderov/features/livestock/domain/event_draft.dart';

void main() {
  test('matches worker event contract', () {
    const draft = EventDraft(
      id: 'id',
      type: 'weight',
      date: '2025-01-01',
      weight: 300.5,
    );
    final actor = {
      'authUserId': 'u',
      'email': 'test@example.com',
      'label': 'Worker',
    };
    final event = draft.toEvent('a', actor, DateTime.utc(2025, 1, 1));
    expect(event['animalId'], 'a');
    expect(event['weight'], 300.5);
    expect(event['performedBy'], actor);
    expect(event['performedAt'], '2025-01-01T00:00:00.000Z');
  });
  test('rejects negative weight, unknown types and an empty note', () {
    expect(
      () => const EventDraft(
        id: 'id',
        type: 'weight',
        date: '2025-01-01',
        weight: -1,
      ).validate(),
      throwsStateError,
    );
    expect(
      () => const EventDraft(
        id: 'id',
        type: 'unknown',
        date: '2025-01-01',
      ).validate(),
      throwsStateError,
    );
  });
  test(
    'accepts manager note and other types without deciding authorization',
    () {
      expect(
        () => const EventDraft(
          id: 'id',
          type: 'note',
          date: '2025-01-01',
          notes: 'Observación',
        ).validate(),
        returnsNormally,
      );
      expect(
        () => const EventDraft(
          id: 'id',
          type: 'other',
          date: '2025-01-01',
        ).validate(),
        returnsNormally,
      );
      expect(
        () => const EventDraft(
          id: 'id',
          type: 'note',
          date: '2025-01-01',
        ).validate(),
        throwsStateError,
      );
    },
  );
  test(
    'rejects impossible date',
    () => expect(
      () => const EventDraft(
        id: 'id',
        type: 'bath',
        date: '2025-02-30',
      ).validate(),
      throwsStateError,
    ),
  );
}
