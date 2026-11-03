import 'dart:io';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/repository.dart';

/// Creates synthetic review data only in an explicitly supplied empty directory.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('请指定全新的隔离验收目录');
  final directory = Directory(args.single).absolute;
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    throw StateError('验收目录必须为空，禁止覆盖现有任务');
  }
  final repository = SpaceRepository(directory);
  await repository.load();
  final today = beijingDay();
  final statuses = [...builtins, 'custom:待确认', 'custom:待审核'];
  final tasks = <SpaceTask>[];
  for (var i = 0; i < statuses.length; i++) {
    final status = statuses[i];
    tasks.add(
      SpaceTask.create(
        status: status,
        projectID: 'review-project',
        due: i == 0 ? '' : dayString(today.add(Duration(days: 3 + i))),
      ).patch({
        'title': ['界面与交互验收', '完善项目需求说明', '整理接口与数据口径', '确认业务验收范围', '核对上线清单'][i],
        'description': '独立合成验收数据，不包含正式任务。',
      }),
    );
  }
  await repository.save(
    SpaceState(
      projects: [Project('review-project', 'Space 界面验收')],
      statuses: statuses,
      tasks: tasks,
      settings: {
        'appearance': 'dark',
        'dark': 'true',
        'navCollapsed': 'true',
        'overviewCollapsed': 'true',
        'viewMode': 'gantt',
      },
    ),
  );
  print('已建立隔离合成数据：${tasks.length}项任务');
}
