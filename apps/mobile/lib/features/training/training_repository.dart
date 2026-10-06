import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'training_models.dart';

class TrainingRepository {
  TrainingRepository(this._ref);

  final Ref _ref;

  Future<List<Course>> courses() async =>
      jsonList(await _ref.read(apiClientProvider).get('/v1/courses')).map(Course.fromJson).toList();

  Future<CourseDetail> course(String id) async =>
      CourseDetail.fromJson(await _ref.read(apiClientProvider).get('/v1/courses/$id') as Json);

  Future<void> setLessonDone(String lessonId, bool done) => done
      ? _ref.read(apiClientProvider).post('/v1/lessons/$lessonId/complete')
      : _ref.read(apiClientProvider).delete('/v1/lessons/$lessonId/complete');

  // Authoring (admin)
  Future<Course> createCourse(Json body) async =>
      Course.fromJson((await _ref.read(apiClientProvider).post('/v1/courses', body) as Json)..putIfAbsent('lessonCount', () => 0));

  Future<void> updateCourse(String id, Json body) => _ref.read(apiClientProvider).patch('/v1/courses/$id', body);

  Future<void> publish(String id, {required bool published}) =>
      _ref.read(apiClientProvider).post('/v1/courses/$id/${published ? 'publish' : 'unpublish'}');

  Future<void> deleteCourse(String id) => _ref.read(apiClientProvider).delete('/v1/courses/$id');

  Future<void> addLesson(String courseId, Json body) => _ref.read(apiClientProvider).post('/v1/courses/$courseId/lessons', body);

  Future<void> updateLesson(String id, Json body) => _ref.read(apiClientProvider).patch('/v1/lessons/$id', body);

  Future<void> deleteLesson(String id) => _ref.read(apiClientProvider).delete('/v1/lessons/$id');

  Future<void> reorderLessons(String courseId, List<String> ids) =>
      _ref.read(apiClientProvider).put('/v1/courses/$courseId/lessons/order', {'ids': ids});

  Future<CourseProgress> progress(String id) async =>
      CourseProgress.fromJson(await _ref.read(apiClientProvider).get('/v1/courses/$id/progress') as Json);
}

final trainingRepositoryProvider = Provider<TrainingRepository>(TrainingRepository.new);

final coursesProvider = FutureProvider.autoDispose<List<Course>>((ref) => ref.watch(trainingRepositoryProvider).courses());

final courseProvider = FutureProvider.autoDispose.family<CourseDetail, String>((ref, id) => ref.watch(trainingRepositoryProvider).course(id));

final courseProgressProvider = FutureProvider.autoDispose.family<CourseProgress, String>((ref, id) => ref.watch(trainingRepositoryProvider).progress(id));
