import 'dart:convert';
import 'dart:io';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';
import 'package:space_flutter/core/sync.dart';

double percentile(List<double> numbers, double q) {
  final sorted = [...numbers]..sort();
  return sorted[((sorted.length - 1) * q).ceil()];
}

Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 1000 : int.parse(args.first);
  final directory = Directory(
    'verification/performance/isolated-$count-${DateTime.now().millisecondsSinceEpoch}',
  )..createSync(recursive: true);
  final repo = SpaceRepository(directory);
  await repo.load();
  final now = timestamp();
  final tasks = List.generate(
    count,
    (i) => SpaceTask(
      id: 'benchmark-${i.toString().padLeft(6, '0')}',
      title: '合成性能任务 ${i + 1}',
      description: '离线任务查询、保存与四视图渲染的合成样本。',
      category: categories.keys.elementAt(i % 3),
      priority: priorities.keys.elementAt(i % 3),
      status: builtins[i % 3],
      createdAt: now,
      updatedAt: now,
      completedAt: i % 3 == 2 ? now : null,
      due: i % 4 == 0
          ? ''
          : dayString(beijingDay().add(Duration(days: i % 14))),
    ),
  );
  var state = await repo.save(SpaceState(tasks: tasks, workspaceID: uid()));
  final query = TaskQuery();
  final queryMs = <double>[], saveMs = <double>[], readMs = <double>[];
  for (var i = 0; i < 30; i++) {
    query.text = i.isEven ? '性能' : '样本';
    query.sort = ['due', 'priority', 'created'][i % 3];
    var timer = Stopwatch()..start();
    query.apply(state, dayString(beijingDay()));
    queryMs.add(timer.elapsedMicroseconds / 1000);
    timer = Stopwatch()..start();
    repo.readFile(repo.path);
    readMs.add(timer.elapsedMicroseconds / 1000);
    if (i < 10) {
      timer = Stopwatch()..start();
      state = await repo.save(
        state.copy(
          tasks: [
            state.tasks.first.patch({
              'title': '合成性能任务 $i',
              'updatedAt': timestamp(),
            }),
            ...state.tasks.skip(1),
          ],
        ),
      );
      saveMs.add(timer.elapsedMicroseconds / 1000);
    }
  }
  final key = SyncCodec.newRecoveryKey();
  final crypto = Stopwatch()..start();
  final packet = await SyncCodec.githubSeal(state, key);
  await SyncCodec.githubOpen(packet, key);
  crypto.stop();
  Map<String, dynamic> stats(List<double> list) => {
    'samples': list.length,
    'medianMs': percentile(list, .5),
    'p95Ms': percentile(list, .95),
    'maxMs': list.reduce((a, b) => a > b ? a : b),
  };
  final report = {
    'taskCount': count,
    'mode': 'Dart AOT standalone core; no UI frame timing',
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version,
    'rssMiB': ProcessInfo.currentRss / 1048576,
    'peakRssMiB': ProcessInfo.maxRss / 1048576,
    'databaseBytes': File(repo.path).lengthSync(),
    'query': stats(queryMs),
    'readValidate': stats(readMs),
    'saveWithBackup': stats(saveMs),
    'encryptDecryptMs': crypto.elapsedMicroseconds / 1000,
    'encryptedBytes': packet.length,
    'formalDataAccessed': false,
  };
  final output = File('verification/performance/core-$count.json');
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  print(const JsonEncoder.withIndent('  ').convert(report));
}
