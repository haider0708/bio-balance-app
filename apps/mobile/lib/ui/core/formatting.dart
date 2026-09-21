import '../../domain/models/tunis_dates.dart';

String dateLabel(String date) => date.contains('T') ? TunisDates.timestampLabel(date) : TunisDates.dateOnlyLabel(date);
