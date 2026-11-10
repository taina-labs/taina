import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/trash/trash_logic.dart';
import 'package:okena_core/okena_core.dart';

FileRecord _file({Zona zona = Zona.casa, String? deletedAt}) {
  return FileRecord(
    rkey: 'f1',
    cid: 'cid',
    blobCid: 'blob',
    sha256: 'sha',
    name: 'arquivo.txt',
    mime: 'text/plain',
    size: 10,
    zona: zona,
    folder: null,
    takenAt: null,
    width: null,
    height: null,
    rendition: Rendition.none,
    deletedAt: deletedAt,
    createdAt: '2026-02-01T09:00:00Z',
    updatedAt: '2026-02-01T09:00:00Z',
  );
}

void main() {
  final now = DateTime(2026, 3, 10, 12);

  group('count label', () {
    test('says carregados while a page is still missing', () {
      expect(
        TrashLogic.countLabel(count: 1, hasMore: true),
        '1 item carregado',
      );
      expect(
        TrashLogic.countLabel(count: 3, hasMore: true),
        '3 itens carregados',
      );
      expect(TrashLogic.countLabel(count: 1, hasMore: false), '1 item');
      expect(TrashLogic.countLabel(count: 3, hasMore: false), '3 itens');
    });
  });

  group('glyph', () {
    test('maps the wire mime to the row glyph', () {
      expect(TrashLogic.glyph('image/png'), TrashGlyph.photo);
      expect(TrashLogic.glyph('video/mp4'), TrashGlyph.film);
      expect(TrashLogic.glyph('audio/mpeg'), TrashGlyph.audio);
      expect(TrashLogic.glyph('application/pdf'), TrashGlyph.pdf);
      expect(TrashLogic.glyph('text/plain'), TrashGlyph.text);
      expect(TrashLogic.glyph('application/zip'), TrashGlyph.document);
    });
  });

  group('meta', () {
    test('today names the day and the days left', () {
      expect(
        TrashLogic.meta(_file(deletedAt: '2026-03-10T09:00:00'), now: now),
        'Apagado hoje, restam 30 dias / Só você',
      );
    });

    test('yesterday and older days read naturally', () {
      expect(
        TrashLogic.meta(_file(deletedAt: '2026-03-09T09:00:00'), now: now),
        'Apagado ontem, restam 29 dias / Só você',
      );
      expect(
        TrashLogic.meta(_file(deletedAt: '2026-03-07T09:00:00'), now: now),
        'Apagado há 3 dias, restam 27 dias / Só você',
      );
    });

    test('the warning window says the purge is close', () {
      expect(
        TrashLogic.meta(
          _file(zona: Zona.praca, deletedAt: '2026-02-10T09:00:00'),
          now: now,
        ),
        'Restam 2 dias, apaga em breve / Todos veem',
      );
      expect(
        TrashLogic.meta(_file(deletedAt: '2026-02-09T09:00:00'), now: now),
        'Resta 1 dia, apaga em breve / Só você',
      );
    });

    test('the last day says it goes today', () {
      expect(
        TrashLogic.meta(_file(deletedAt: '2026-02-08T09:00:00'), now: now),
        'Apaga hoje / Só você',
      );
    });

    test('a clock ahead of the box never reads negative days', () {
      expect(
        TrashLogic.meta(_file(deletedAt: '2026-03-12T09:00:00'), now: now),
        'Apagado hoje, restam 30 dias / Só você',
      );
    });

    test('an unparsable deletion falls back to the sent date', () {
      expect(
        TrashLogic.meta(_file(deletedAt: 'ontem'), now: now),
        'Apagado em ontem / Só você',
      );
      expect(
        TrashLogic.meta(_file(deletedAt: null), now: now),
        'Apagado em  / Só você',
      );
    });
  });

  group('warning', () {
    test('starts inside the warning window', () {
      expect(
        TrashLogic.isWarning(_file(deletedAt: '2026-02-10T09:00:00'), now: now),
        isTrue,
      );
      expect(
        TrashLogic.isWarning(_file(deletedAt: '2026-02-05T09:00:00'), now: now),
        isTrue,
      );
    });

    test('is false with room left and for an unknown date', () {
      expect(
        TrashLogic.isWarning(_file(deletedAt: '2026-03-07T09:00:00'), now: now),
        isFalse,
      );
      expect(
        TrashLogic.isWarning(_file(deletedAt: 'ontem'), now: now),
        isFalse,
      );
      expect(TrashLogic.isWarning(_file(), now: now), isFalse);
    });
  });
}
