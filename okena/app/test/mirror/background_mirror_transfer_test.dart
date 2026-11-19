import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:okena_app/src/mirror/background_mirror_transfer.dart';
import 'package:okena_core/okena_core.dart';

const _sha256 =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const _otherSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('BackgroundMirrorTransfer scheduling', () {
    test(
      'enqueues a multipart upload with mirror defaults and metadata',
      () async {
        final fixture = await _fixture();
        final result = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(result, isA<Ok<void>>());
        expect(fixture.gateway.enqueueCalls, hasLength(1));
        expect(fixture.requestCalls, 1);
        final task = fixture.gateway.enqueueCalls.single;
        expect(task.taskId, 'mirror-task');
        expect(task.url, 'https://community.example/api/v1/files');
        expect(task.httpRequestMethod, 'POST');
        expect(task.headers['Authorization'], 'Bearer token-for-request-only');
        expect(task.fileField, 'file');
        expect(task.fields, {'folder': 'folder-rkey'});
        expect(task.filename, 'local-object.bin');
        expect(task.mimeType, 'image/jpeg');
        expect(task.displayName, 'Camera roll photo.jpg');
        expect(task.baseDirectory, BaseDirectory.applicationSupport);
        expect(task.directory, 'mirror/stable');
        expect(task.updates, Updates.statusAndProgress);
        expect(task.requiresWiFi, isTrue);
        expect(task.retries, 0);
        expect(task.allowPause, isFalse);
        expect(task.group, BackgroundMirrorTransfer.mirrorGroup);

        final metadata = jsonDecode(task.metaData) as Map<String, dynamic>;
        expect(metadata, {
          'ownerId': 'owner-1',
          'assetId': 'asset-1',
          'modificationDate':
              fixture.entry.modificationDate.microsecondsSinceEpoch,
          'sha256': _sha256,
        });
        expect(task.metaData, isNot(contains('community.example')));
        expect(task.metaData, isNot(contains('token-for-request-only')));
        expect(fixture.gateway.splitPaths, [fixture.file.path]);
      },
    );

    test('can opt out of the Wi-Fi requirement', () async {
      final fixture = await _fixture(requiresWiFi: false);

      final result = await fixture.transfer.ensureStarted(
        entry: fixture.entry,
        folderRkey: 'folder-rkey',
      );

      expect(result, isA<Ok<void>>());
      expect(fixture.gateway.enqueueCalls.single.requiresWiFi, isFalse);
      expect(fixture.gateway.enqueueCalls.single.retries, 0);
    });

    test(
      'Wi-Fi provider applies changes only to subsequently enqueued tasks',
      () async {
        var requiresWiFi = true;
        final fixture = await _fixture(
          requiresWiFiProvider: () => requiresWiFi,
        );

        final first = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );
        requiresWiFi = false;
        final second = await fixture.transfer.ensureStarted(
          entry: fixture.entry.copyWith(
            assetId: 'asset-2',
            backgroundTaskId: 'next-task',
          ),
          folderRkey: 'folder-rkey',
        );

        expect(first, isA<Ok<void>>());
        expect(second, isA<Ok<void>>());
        expect(fixture.gateway.enqueueCalls.map((task) => task.requiresWiFi), [
          true,
          false,
        ]);
      },
    );

    test(
      'reattaches to a matching task without requesting credentials',
      () async {
        final fixture = await _fixture();
        fixture.gateway.tasks['mirror-task'] = _task(
          taskId: 'mirror-task',
          ownerId: 'owner-1',
        );

        final result = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(result, isA<Ok<void>>());
        expect(fixture.requestCalls, 0);
        expect(fixture.gateway.enqueueCalls, isEmpty);
      },
    );

    test(
      'rejects existing task collisions and another asset revision',
      () async {
        final ownerFixture = await _fixture();
        ownerFixture.gateway.tasks['mirror-task'] = _task(
          taskId: 'mirror-task',
          ownerId: 'another-owner',
        );
        final wrongOwner = await ownerFixture.transfer.ensureStarted(
          entry: ownerFixture.entry,
          folderRkey: 'folder-rkey',
        );
        expect(wrongOwner.error, isA<MirrorTransferRejected>());
        expect(ownerFixture.requestCalls, 0);
        expect(ownerFixture.gateway.enqueueCalls, isEmpty);

        final revisionFixture = await _fixture();
        revisionFixture.gateway.tasks['mirror-task'] = _task(
          taskId: 'mirror-task',
          ownerId: 'owner-1',
          modificationDate: DateTime.utc(2026, 11, 18, 12, 31),
        );
        final wrongRevision = await revisionFixture.transfer.ensureStarted(
          entry: revisionFixture.entry,
          folderRkey: 'folder-rkey',
        );
        expect(wrongRevision.error, isA<MirrorTransferRejected>());
        expect(revisionFixture.requestCalls, 0);
        expect(revisionFixture.gateway.enqueueCalls, isEmpty);
      },
    );

    test(
      'complete records without a replayed response emit one failure',
      () async {
        final fixture = await _fixture();
        final task = _task(taskId: 'mirror-task', ownerId: 'owner-1');
        fixture.gateway.records['mirror-task'] = _record(
          task,
          TaskStatus.complete,
        );
        final events = <MirrorTransferEvent>[];
        final subscription = fixture.transfer.events.listen(events.add);

        final first = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );
        final second = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(first, isA<Ok<void>>());
        expect(second, isA<Ok<void>>());
        expect(fixture.gateway.taskLookupCalls, 2);
        expect(fixture.gateway.recordLookupCalls, 2);
        expect(fixture.requestCalls, 0);
        expect(fixture.gateway.enqueueCalls, isEmpty);
        expect(events, hasLength(1));
        expect(events.single, isA<MirrorTransferFailed>());
        final failure = events.single as MirrorTransferFailed;
        expect(failure.assetId, fixture.entry.assetId);
        expect(failure.taskId, 'mirror-task');
        expect(failure.error, isA<InvalidResponseError>());
        expect(
          (failure.error as InvalidResponseError).cause,
          'mirror upload completed response is missing',
        );
        await subscription.cancel();
      },
    );

    test(
      'a replayed valid completion response resolves a complete record',
      () async {
        final fixture = await _fixture();
        final task = _task(taskId: 'mirror-task', ownerId: 'owner-1');
        fixture.gateway.records['mirror-task'] = _record(
          task,
          TaskStatus.complete,
        );
        final events = <MirrorTransferEvent>[];
        final subscription = fixture.transfer.events.listen(events.add);

        fixture.gateway.addUpdate(
          TaskStatusUpdate(
            task,
            TaskStatus.complete,
            null,
            _fileJson(_sha256),
            null,
            201,
          ),
        );
        final result = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(result, isA<Ok<void>>());
        expect(events, hasLength(1));
        expect(events.single, isA<MirrorTransferCompleted>());
        expect(fixture.requestCalls, 0);
        expect(fixture.gateway.enqueueCalls, isEmpty);
        await subscription.cancel();
      },
    );

    test(
      'rejects a database record belonging to a different revision',
      () async {
        final fixture = await _fixture();
        fixture.gateway.records['mirror-task'] = _record(
          _task(
            taskId: 'mirror-task',
            ownerId: 'owner-1',
            expectedSha256: _otherSha256,
          ),
          TaskStatus.running,
        );

        final result = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(result.error, isA<MirrorTransferRejected>());
        expect(fixture.requestCalls, 0);
        expect(fixture.gateway.enqueueCalls, isEmpty);
      },
    );

    test('final failure records win over native tasks and emit once', () async {
      final statuses = <(TaskStatus, TaskException?, Type)>[
        (
          TaskStatus.failed,
          TaskConnectionException('network failed'),
          NetworkError,
        ),
        (
          TaskStatus.notFound,
          TaskHttpException(
            '{"error":{"code":"not_found","message":"missing"}}',
            404,
          ),
          ApiError,
        ),
        (TaskStatus.canceled, null, CancelledError),
      ];

      for (final (status, exception, expectedErrorType) in statuses) {
        final fixture = await _fixture();
        final task = _task(taskId: 'mirror-task', ownerId: 'owner-1');
        fixture.gateway.tasks['mirror-task'] = task;
        fixture.gateway.records['mirror-task'] = _record(
          task,
          status,
          exception: exception,
        );
        final events = <MirrorTransferEvent>[];
        final subscription = fixture.transfer.events.listen(events.add);

        final first = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );
        final second = await fixture.transfer.ensureStarted(
          entry: fixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(first, isA<Ok<void>>());
        expect(second, isA<Ok<void>>());
        expect(events, hasLength(1));
        expect(events.single, isA<MirrorTransferFailed>());
        expect(
          (events.single as MirrorTransferFailed).error.runtimeType,
          expectedErrorType,
        );
        expect(fixture.requestCalls, 0);
        expect(fixture.gateway.enqueueCalls, isEmpty);
        await subscription.cancel();
      }
    });

    test('rebuilds a killed nonfinal task with the same task ID', () async {
      final fixture = await _fixture();
      final task = _task(taskId: 'mirror-task', ownerId: 'owner-1');
      fixture.gateway.records['mirror-task'] = _record(
        task,
        TaskStatus.running,
      );

      final result = await fixture.transfer.ensureStarted(
        entry: fixture.entry,
        folderRkey: 'folder-rkey',
      );

      expect(result, isA<Ok<void>>());
      expect(fixture.gateway.enqueueCalls, hasLength(1));
      expect(fixture.gateway.enqueueCalls.single.taskId, 'mirror-task');
      expect(fixture.requestCalls, 1);
    });

    test('serializes concurrent ensure calls to one enqueue', () async {
      final fixture = await _fixture();
      final enteredEnqueue = Completer<void>();
      final releaseEnqueue = Completer<void>();
      fixture.gateway.enqueueHandler = (task) async {
        enteredEnqueue.complete();
        await releaseEnqueue.future;
        fixture.gateway.tasks[task.taskId] = task;
        return true;
      };

      final first = fixture.transfer.ensureStarted(
        entry: fixture.entry,
        folderRkey: 'folder-rkey',
      );
      await enteredEnqueue.future;
      final second = fixture.transfer.ensureStarted(
        entry: fixture.entry,
        folderRkey: 'folder-rkey',
      );
      releaseEnqueue.complete();

      expect(await first, isA<Ok<void>>());
      expect(await second, isA<Ok<void>>());
      expect(fixture.gateway.enqueueCalls, hasLength(1));
      expect(fixture.requestCalls, 1);
    });

    test(
      'classifies request rejection and pre-enqueue exceptions as rejected',
      () async {
        const apiError = ApiError(
          code: 'not_signed_in',
          status: 401,
          serverMessage: 'Please sign in',
        );
        final rejectedFixture = await _fixture(
          requestProvider: () async => const Err<HttpRequest>(apiError),
        );
        final rejected = await rejectedFixture.transfer.ensureStarted(
          entry: rejectedFixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(rejected.error, isA<MirrorTransferRejected>());
        expect((rejected.error! as MirrorTransferRejected).cause, apiError);
        expect(rejectedFixture.gateway.enqueueCalls, isEmpty);

        final exceptionFixture = await _fixture();
        exceptionFixture.gateway.splitHandler = (_) async {
          throw const FileSystemException('path split failed');
        };
        final exceptionResult = await exceptionFixture.transfer.ensureStarted(
          entry: exceptionFixture.entry,
          folderRkey: 'folder-rkey',
        );

        expect(exceptionResult.error, isA<MirrorTransferRejected>());
        expect(exceptionFixture.gateway.enqueueCalls, isEmpty);
      },
    );

    test('classifies enqueue and lookup exceptions as uncertain', () async {
      final enqueueFixture = await _fixture();
      enqueueFixture.gateway.enqueueHandler = (_) async {
        throw PlatformException(
          code: 'enqueue',
          message: 'enqueue outcome unknown',
        );
      };
      final enqueueResult = await enqueueFixture.transfer.ensureStarted(
        entry: enqueueFixture.entry,
        folderRkey: 'folder-rkey',
      );
      expect(enqueueResult.error, isA<MirrorTransferUncertain>());

      final lookupFixture = await _fixture();
      lookupFixture.gateway.taskForIdHandler = (_) async {
        throw PlatformException(
          code: 'task_lookup',
          message: 'task store unavailable',
        );
      };
      final lookupResult = await lookupFixture.transfer.ensureStarted(
        entry: lookupFixture.entry,
        folderRkey: 'folder-rkey',
      );
      expect(lookupResult.error, isA<MirrorTransferUncertain>());
      expect(lookupFixture.gateway.enqueueCalls, isEmpty);

      final recordFixture = await _fixture();
      recordFixture.gateway.recordForIdHandler = (_) async {
        throw PlatformException(
          code: 'record_lookup',
          message: 'task record unavailable',
        );
      };
      final recordResult = await recordFixture.transfer.ensureStarted(
        entry: recordFixture.entry,
        folderRkey: 'folder-rkey',
      );
      expect(recordResult.error, isA<MirrorTransferUncertain>());
      expect(recordFixture.gateway.enqueueCalls, isEmpty);
    });

    test('starts before lookup and rejects when startup fails', () async {
      final fixture = await _fixture();
      fixture.gateway.startHandler = () async {
        fixture.gateway.startCalls += 1;
        throw PlatformException(code: 'start', message: 'database unavailable');
      };

      final result = await fixture.transfer.ensureStarted(
        entry: fixture.entry,
        folderRkey: 'folder-rkey',
      );

      expect(result.error, isA<MirrorTransferRejected>());
      expect(
        (result.error! as MirrorTransferRejected).cause,
        isA<NetworkError>(),
      );
      expect(fixture.gateway.startCalls, 1);
      expect(fixture.gateway.taskLookupCalls, 0);
      expect(fixture.gateway.enqueueCalls, isEmpty);
    });

    test(
      'does not follow symlinks when validating the local upload file',
      () async {
        final fixture = await _fixture();
        final link = Link('${fixture.root.path}/linked-object');
        await link.create(fixture.file.path);

        final result = await fixture.transfer.ensureStarted(
          entry: fixture.entry.copyWith(localPath: link.path),
          folderRkey: 'folder-rkey',
        );

        expect(result.error, isA<MirrorTransferRejected>());
        expect(fixture.requestCalls, 0);
        expect(fixture.gateway.enqueueCalls, isEmpty);
      },
    );

    test('reroots a stale container path under current application support', () async {
      final fixture = await _fixture();
      final supportDirectory = Directory(
        '${fixture.root.path}/current-support',
      );
      final stablePath = File(
        '${supportDirectory.path}/taina_mirror/album/local-object.bin',
      );
      await stablePath.parent.create(recursive: true);
      await stablePath.writeAsString('abc');
      var providerCalls = 0;
      var requestCalls = 0;

      final transfer = BackgroundMirrorTransfer(
        ownerId: 'owner-1',
        gateway: fixture.gateway,
        requestProvider: () async {
          requestCalls += 1;
          return Ok(
            HttpRequest(
              url: Uri.parse('https://community.example/api/v1/files'),
              method: 'POST',
            ),
          );
        },
        supportDirectoryProvider: () async {
          providerCalls += 1;
          return supportDirectory;
        },
      );
      addTearDown(transfer.dispose);
      final result = await transfer.ensureStarted(
        entry: fixture.entry.copyWith(
          localPath:
              '/old/container/app-support/taina_mirror/album/local-object.bin',
        ),
        folderRkey: 'folder-rkey',
      );

      expect(result, isA<Ok<void>>());
      expect(providerCalls, 1);
      expect(requestCalls, 1);
      expect(fixture.gateway.splitPaths, [stablePath.path]);
      expect(fixture.gateway.enqueueCalls.single.filename, 'local-object.bin');
    });

    test('rejects Task.split paths rooted at BaseDirectory.root', () async {
      final fixture = await _fixture();
      fixture.gateway.splitHandler = (_) async =>
          (BaseDirectory.root, fixture.root.path, 'local-object.bin');

      final result = await fixture.transfer.ensureStarted(
        entry: fixture.entry,
        folderRkey: 'folder-rkey',
      );

      expect(result.error, isA<MirrorTransferRejected>());
      expect(fixture.gateway.enqueueCalls, isEmpty);
    });

    test(
      'rechecks a false enqueue and rejects only when no task exists',
      () async {
        final acceptedFixture = await _fixture();
        acceptedFixture.gateway.enqueueHandler = (task) async {
          acceptedFixture.gateway.tasks[task.taskId] = task;
          return false;
        };
        final accepted = await acceptedFixture.transfer.ensureStarted(
          entry: acceptedFixture.entry,
          folderRkey: 'folder-rkey',
        );
        expect(accepted, isA<Ok<void>>());

        final rejectedFixture = await _fixture();
        rejectedFixture.gateway.enqueueHandler = (_) async => false;
        final rejected = await rejectedFixture.transfer.ensureStarted(
          entry: rejectedFixture.entry,
          folderRkey: 'folder-rkey',
        );
        expect(rejected.error, isA<MirrorTransferRejected>());
        expect(
          (rejected.error! as MirrorTransferRejected).cause,
          isA<MirrorAssetReadError>(),
        );
      },
    );
  });

  group('BackgroundMirrorTransfer lifecycle', () {
    test(
      'keeps one native single-subscription listener across adapter disposal',
      () async {
        final gateway = _FakeGateway(singleSubscriptionUpdates: true);
        final first = BackgroundMirrorTransfer(
          ownerId: 'owner-1',
          gateway: gateway,
          requestProvider: _requestProvider,
        );
        await first.dispose();

        final second = BackgroundMirrorTransfer(
          ownerId: 'owner-1',
          gateway: gateway,
          requestProvider: _requestProvider,
        );
        final events = <MirrorTransferEvent>[];
        final subscription = second.events.listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await second.dispose();
          await gateway.close();
        });

        gateway.addUpdate(
          TaskProgressUpdate(
            _task(taskId: 'reattached-task', ownerId: 'owner-1'),
            0.6,
          ),
        );
        gateway.addUpdate(
          TaskStatusUpdate(
            _task(taskId: 'reattached-task', ownerId: 'owner-1'),
            TaskStatus.canceled,
          ),
        );
        gateway.addError(
          PlatformException(
            code: 'native_updates',
            message: 'native update stream failed',
          ),
        );

        expect(events, hasLength(3));
        expect(events[0], isA<MirrorTransferProgress>());
        expect((events[0] as MirrorTransferProgress).value, 0.6);
        expect(events[1], isA<MirrorTransferFailed>());
        expect(
          (events[1] as MirrorTransferFailed).error,
          isA<CancelledError>(),
        );
        expect(events[2], isA<MirrorTransferStreamFailed>());
        expect(
          ((events[2] as MirrorTransferStreamFailed).error as NetworkError)
              .cause,
          contains('native update stream failed'),
        );
      },
    );

    test(
      'cancel is idempotent for missing tasks and accepts successful cancel',
      () async {
        final fixture = await _fixture();

        expect(await fixture.transfer.cancel('missing-task'), isA<Ok<void>>());

        fixture.gateway.tasks['active-task'] = _task(
          taskId: 'active-task',
          ownerId: 'owner-1',
        );
        expect(await fixture.transfer.cancel('active-task'), isA<Ok<void>>());
        expect(fixture.gateway.tasks, isEmpty);
      },
    );

    test('cancel reports a still-active task and turns plugin exceptions into errors', () async {
      final fixture = await _fixture();
      fixture.gateway.tasks['active-task'] = _task(
        taskId: 'active-task',
        ownerId: 'owner-1',
      );
      fixture.gateway.cancelHandler = (_) async => false;

      final stillActive = await fixture.transfer.cancel('active-task');
      expect(stillActive.error, isA<MirrorAssetReadError>());

      fixture.gateway.cancelHandler = (_) async {
        throw PlatformException(code: 'cancel', message: 'cancel failed');
      };
      final failed = await fixture.transfer.cancel('active-task');
      expect(failed.error, isA<MirrorAssetReadError>());
    });

    test(
      'start caches success and retries after initialization failure',
      () async {
        final fixture = await _fixture();
        fixture.gateway.startHandler = () async {
          fixture.gateway.startCalls += 1;
          if (fixture.gateway.startCalls == 1) {
            throw PlatformException(code: 'start', message: 'start failed');
          }
        };

        final first = await fixture.transfer.start();
        final second = await fixture.transfer.start();
        final third = await fixture.transfer.start();

        expect(first.error, isA<NetworkError>());
        expect(second, isA<Ok<void>>());
        expect(third, isA<Ok<void>>());
        expect(fixture.gateway.startCalls, 2);
      },
    );

    test('empty owner and disposed operations return local errors', () async {
      final emptyOwner = await _fixture(ownerId: '');
      expect(
        (await emptyOwner.transfer.start()).error,
        isA<MirrorAssetReadError>(),
      );
      expect(
        (await emptyOwner.transfer.ensureStarted(
          entry: emptyOwner.entry,
          folderRkey: 'folder-rkey',
        )).error,
        isA<MirrorTransferRejected>(),
      );
      expect(
        (await emptyOwner.transfer.cancel('task')).error,
        isA<MirrorAssetReadError>(),
      );
      expect(emptyOwner.gateway.startCalls, 0);
      expect(emptyOwner.gateway.taskLookupCalls, 0);

      final disposed = await _fixture();
      await disposed.transfer.dispose();
      expect(
        (await disposed.transfer.start()).error,
        isA<MirrorAssetReadError>(),
      );
      expect(
        (await disposed.transfer.ensureStarted(
          entry: disposed.entry,
          folderRkey: 'folder-rkey',
        )).error,
        isA<MirrorTransferRejected>(),
      );
      expect(
        (await disposed.transfer.cancel('task')).error,
        isA<MirrorAssetReadError>(),
      );
      expect(disposed.gateway.startCalls, 0);
      expect(disposed.gateway.taskLookupCalls, 0);
      expect(disposed.gateway.cancelCalls, 0);
    });
  });

  group('BackgroundMirrorTransfer events', () {
    test(
      'filters progress by group and owner and ignores special values',
      () async {
        final fixture = await _fixture();
        final events = <MirrorTransferEvent>[];
        final subscription = fixture.transfer.events.listen(events.add);

        fixture.gateway.addUpdate(
          TaskProgressUpdate(_task(taskId: 'task-1', ownerId: 'owner-1'), 0.4),
        );
        fixture.gateway.addUpdate(
          TaskProgressUpdate(_task(taskId: 'task-1', ownerId: 'owner-1'), -1),
        );
        fixture.gateway.addUpdate(
          TaskProgressUpdate(
            _task(taskId: 'task-1', ownerId: 'owner-1'),
            double.nan,
          ),
        );
        fixture.gateway.addUpdate(
          TaskProgressUpdate(_task(taskId: 'other', ownerId: 'owner-2'), 0.8),
        );
        fixture.gateway.addUpdate(
          TaskProgressUpdate(
            _task(
              taskId: 'wrong-group',
              ownerId: 'owner-1',
              group: 'unrelated',
            ),
            0.8,
          ),
        );
        fixture.gateway.addUpdate(
          TaskProgressUpdate(
            DownloadTask(
              taskId: 'download',
              url: 'https://community.example/file',
              filename: 'download.bin',
              group: BackgroundMirrorTransfer.mirrorGroup,
              metaData: _metadata(ownerId: 'owner-1'),
            ),
            0.8,
          ),
        );

        expect(events, hasLength(1));
        expect(events.single, isA<MirrorTransferProgress>());
        final progress = events.single as MirrorTransferProgress;
        expect(progress.assetId, 'asset-1');
        expect(progress.taskId, 'task-1');
        expect(progress.value, 0.4);
        await subscription.cancel();
      },
    );

    test(
      'decodes success and retains metadata date and expected hash',
      () async {
        final fixture = await _fixture();
        final events = <MirrorTransferEvent>[];
        final subscription = fixture.transfer.events.listen(events.add);
        final task = _task(taskId: 'completed-task', ownerId: 'owner-1');

        fixture.gateway.addUpdate(
          TaskStatusUpdate(
            task,
            TaskStatus.complete,
            null,
            _fileJson(_sha256),
            const {'content-type': 'application/json'},
            201,
          ),
        );

        expect(events, hasLength(1));
        expect(events.single, isA<MirrorTransferCompleted>());
        final completed = events.single as MirrorTransferCompleted;
        expect(completed.assetId, 'asset-1');
        expect(completed.taskId, 'completed-task');
        expect(completed.modificationDate, fixture.entry.modificationDate);
        expect(completed.modificationDate.isUtc, isTrue);
        expect(completed.file.sha256, _sha256);
        expect(completed.file.rkey, 'file-rkey');
        await subscription.cancel();
      },
    );

    test(
      'malformed responses and hash mismatches fail as invalid responses',
      () async {
        final fixture = await _fixture();
        final events = <MirrorTransferEvent>[];
        final subscription = fixture.transfer.events.listen(events.add);

        fixture.gateway.addUpdate(
          TaskStatusUpdate(
            _task(taskId: 'malformed', ownerId: 'owner-1'),
            TaskStatus.complete,
            null,
            '{',
            null,
            200,
          ),
        );
        fixture.gateway.addUpdate(
          TaskStatusUpdate(
            _task(taskId: 'missing', ownerId: 'owner-1'),
            TaskStatus.complete,
            null,
            null,
            null,
            200,
          ),
        );
        fixture.gateway.addUpdate(
          TaskStatusUpdate(
            _task(taskId: 'wrong-hash', ownerId: 'owner-1'),
            TaskStatus.complete,
            null,
            _fileJson(_otherSha256),
            null,
            200,
          ),
        );

        expect(events, hasLength(3));
        for (final event in events) {
          expect(event, isA<MirrorTransferFailed>());
          expect(
            (event as MirrorTransferFailed).error,
            isA<InvalidResponseError>(),
          );
        }
        await subscription.cancel();
      },
    );

    test('maps HTTP envelopes through the core API failure decoder', () async {
      final fixture = await _fixture();
      final events = <MirrorTransferEvent>[];
      final subscription = fixture.transfer.events.listen(events.add);

      fixture.gateway.addUpdate(
        TaskStatusUpdate(
          _task(taskId: 'unauthorized', ownerId: 'owner-1'),
          TaskStatus.failed,
          TaskHttpException('Unauthorized', 401),
          jsonEncode({
            'error': {
              'code': 'account_deactivated',
              'message': 'This device is no longer active',
              'details': {
                'device': ['revoked'],
              },
            },
          }),
          const {'www-authenticate': 'Bearer'},
          500,
        ),
      );
      fixture.gateway.addUpdate(
        TaskStatusUpdate(
          _task(taskId: 'quota', ownerId: 'owner-1'),
          TaskStatus.failed,
          TaskHttpException(
            jsonEncode({
              'error': {
                'code': 'storage_quota_exceeded',
                'message': 'There is no space left',
                'details': {
                  'storage': ['full'],
                },
              },
            }),
            413,
          ),
          null,
          const {'content-type': 'application/json'},
          413,
        ),
      );

      expect(events, hasLength(2));
      final unauthorized = (events[0] as MirrorTransferFailed).error;
      expect(unauthorized, isA<ApiError>());
      expect((unauthorized as ApiError).status, 401);
      expect(unauthorized.code, 'account_deactivated');
      expect(unauthorized.details['device'], ['revoked']);

      final quota = (events[1] as MirrorTransferFailed).error;
      expect(quota, isA<ApiError>());
      expect((quota as ApiError).status, 413);
      expect(quota.code, 'storage_quota_exceeded');
      expect(quota.isQuotaExceeded, isTrue);
      expect(quota.details['storage'], ['full']);
      await subscription.cancel();
    });

    test('maps native network and cancellation failures', () async {
      final fixture = await _fixture();
      final events = <MirrorTransferEvent>[];
      final subscription = fixture.transfer.events.listen(events.add);

      fixture.gateway.addUpdate(
        TaskStatusUpdate(
          _task(taskId: 'network', ownerId: 'owner-1'),
          TaskStatus.failed,
          TaskConnectionException('socket disconnected'),
        ),
      );
      fixture.gateway.addUpdate(
        TaskStatusUpdate(
          _task(taskId: 'cancelled', ownerId: 'owner-1'),
          TaskStatus.canceled,
        ),
      );

      expect(events, hasLength(2));
      final network = (events[0] as MirrorTransferFailed).error;
      expect(network, isA<NetworkError>());
      expect((network as NetworkError).cause, 'socket disconnected');
      expect((events[1] as MirrorTransferFailed).error, isA<CancelledError>());
      await subscription.cancel();
    });

    test('forwards updates stream errors as transfer failures', () async {
      final fixture = await _fixture();
      final events = <MirrorTransferEvent>[];
      final subscription = fixture.transfer.events.listen(events.add);

      fixture.gateway.addError(
        PlatformException(code: 'updates', message: 'update stream failed'),
      );

      expect(events, hasLength(1));
      expect(events.single, isA<MirrorTransferStreamFailed>());
      final failure = events.single as MirrorTransferStreamFailed;
      expect(failure.error, isA<NetworkError>());
      expect(
        (failure.error as NetworkError).cause,
        contains('update stream failed'),
      );
      await subscription.cancel();
    });
  });
}

Future<_Fixture> _fixture({
  bool requiresWiFi = true,
  bool Function()? requiresWiFiProvider,
  String ownerId = 'owner-1',
  MirrorUploadRequestProvider? requestProvider,
  MirrorSupportDirectoryProvider? supportDirectoryProvider,
}) async {
  final root = await Directory.systemTemp.createTemp('background-mirror-');
  final file = File('${root.path}/local-object.bin');
  await file.writeAsString('abc');
  final gateway = _FakeGateway();
  var requestCalls = 0;
  final transfer = BackgroundMirrorTransfer(
    ownerId: ownerId,
    gateway: gateway,
    requiresWiFi: requiresWiFi,
    requiresWiFiProvider: requiresWiFiProvider,
    supportDirectoryProvider: supportDirectoryProvider,
    requestProvider:
        requestProvider ??
        () async {
          requestCalls += 1;
          return Ok(
            HttpRequest(
              url: Uri.parse('https://community.example/api/v1/files'),
              method: 'POST',
              headers: const {'Authorization': 'Bearer token-for-request-only'},
            ),
          );
        },
  );
  addTearDown(() async {
    await transfer.dispose();
    await gateway.close();
    await root.delete(recursive: true);
  });
  return _Fixture(
    root: root,
    file: file,
    gateway: gateway,
    transfer: transfer,
    entry: _entry(localPath: file.path),
    getRequestCalls: () => requestCalls,
  );
}

Future<TainaResult<HttpRequest>> _requestProvider() async => Ok(
  HttpRequest(
    url: Uri.parse('https://community.example/api/v1/files'),
    method: 'POST',
  ),
);

MirrorEntry _entry({
  String? localPath = '/tmp/local-object.bin',
  String? sha256 = _sha256,
  String? taskId = 'mirror-task',
}) => MirrorEntry(
  assetId: 'asset-1',
  modificationDate: DateTime.utc(2026, 11, 18, 12, 30),
  filename: 'Camera roll photo.jpg',
  mime: 'image/jpeg',
  size: 3,
  takenAt: null,
  sha256: sha256,
  localPath: localPath,
  state: MirrorState.uploading,
  rkey: null,
  backgroundTaskId: taskId,
  attempts: 0,
  lastError: null,
  progress: 0,
  updatedAt: DateTime.utc(2026, 11, 18, 12, 30),
);

UploadTask _task({
  required String taskId,
  required String ownerId,
  String group = BackgroundMirrorTransfer.mirrorGroup,
  String expectedSha256 = _sha256,
  String assetId = 'asset-1',
  DateTime? modificationDate,
}) => UploadTask(
  taskId: taskId,
  url: 'https://community.example/api/v1/files',
  filename: 'local-object.bin',
  group: group,
  metaData: _metadata(
    ownerId: ownerId,
    expectedSha256: expectedSha256,
    assetId: assetId,
    modificationDate: modificationDate,
  ),
);

String _metadata({
  required String ownerId,
  String expectedSha256 = _sha256,
  String assetId = 'asset-1',
  DateTime? modificationDate,
}) => jsonEncode({
  'ownerId': ownerId,
  'assetId': assetId,
  'modificationDate': (modificationDate ?? DateTime.utc(2026, 11, 18, 12, 30))
      .toUtc()
      .microsecondsSinceEpoch,
  'sha256': expectedSha256,
});

TaskRecord _record(Task task, TaskStatus status, {TaskException? exception}) =>
    TaskRecord(task, status, 0, -1, exception);

String _fileJson(String sha256) => jsonEncode({
  'rkey': 'file-rkey',
  'cid': 'record-cid',
  'blob_cid': 'blob-cid',
  'sha256': sha256,
  'name': 'Camera roll photo.jpg',
  'mime': 'image/jpeg',
  'size': 3,
  'zona': 'casa',
  'folder': 'folder-rkey',
  'taken_at': null,
  'width': null,
  'height': null,
  'rendition': 'none',
  'deleted_at': null,
  'created_at': '2026-11-18T12:30:00Z',
  'updated_at': '2026-11-18T12:30:00Z',
});

final class _Fixture {
  const _Fixture({
    required this.root,
    required this.file,
    required this.gateway,
    required this.transfer,
    required this.entry,
    required this.getRequestCalls,
  });

  final Directory root;
  final File file;
  final _FakeGateway gateway;
  final BackgroundMirrorTransfer transfer;
  final MirrorEntry entry;
  final int Function() getRequestCalls;

  int get requestCalls => getRequestCalls();
}

final class _FakeGateway implements BackgroundDownloaderGateway {
  _FakeGateway({bool singleSubscriptionUpdates = false})
    : _updates = singleSubscriptionUpdates
          ? StreamController<TaskUpdate>(sync: true)
          : StreamController<TaskUpdate>.broadcast(sync: true);

  final StreamController<TaskUpdate> _updates;
  final Map<String, Task> tasks = {};
  final List<UploadTask> enqueueCalls = [];
  final List<String> splitPaths = [];
  int startCalls = 0;
  int taskLookupCalls = 0;
  int recordLookupCalls = 0;
  int cancelCalls = 0;
  final Map<String, TaskRecord> records = {};

  Future<void> Function()? startHandler;
  Future<Task?> Function(String taskId)? taskForIdHandler;
  Future<TaskRecord?> Function(String taskId)? recordForIdHandler;
  Future<(BaseDirectory, String, String)> Function(String path)? splitHandler;
  Future<bool> Function(UploadTask task)? enqueueHandler;
  Future<bool> Function(String taskId)? cancelHandler;

  @override
  Stream<TaskUpdate> get updates => _updates.stream;

  void addUpdate(TaskUpdate update) => _updates.add(update);
  void addError(Object error) => _updates.addError(error, StackTrace.current);

  @override
  Future<void> start() async {
    final handler = startHandler;
    if (handler != null) {
      await handler();
      return;
    }
    startCalls += 1;
  }

  @override
  Future<Task?> taskForId(String taskId) async {
    taskLookupCalls += 1;
    final handler = taskForIdHandler;
    if (handler != null) return handler(taskId);
    return tasks[taskId];
  }

  @override
  Future<TaskRecord?> recordForId(String taskId) async {
    recordLookupCalls += 1;
    final handler = recordForIdHandler;
    if (handler != null) return handler(taskId);
    return records[taskId];
  }

  @override
  Future<(BaseDirectory, String, String)> split(String filePath) async {
    splitPaths.add(filePath);
    final handler = splitHandler;
    if (handler != null) return handler(filePath);
    return (
      BaseDirectory.applicationSupport,
      'mirror/stable',
      'local-object.bin',
    );
  }

  @override
  Future<bool> enqueue(UploadTask task) async {
    enqueueCalls.add(task);
    final handler = enqueueHandler;
    if (handler != null) return handler(task);
    tasks[task.taskId] = task;
    return true;
  }

  @override
  Future<bool> cancel(String taskId) async {
    cancelCalls += 1;
    final handler = cancelHandler;
    if (handler != null) return handler(taskId);
    return tasks.remove(taskId) != null;
  }

  Future<void> close() => _updates.close();
}
