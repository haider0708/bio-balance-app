/// Net points earned in one store month; spending is excluded by the server.
class RankingScore {
  final String userId, name;
  final int points, rank;
  const RankingScore(this.userId, this.name, this.points, this.rank);
}

class StoreRanking {
  final String month;
  final List<RankingScore> scores;
  StoreRanking(this.month, Iterable<RankingScore> scores)
    : scores = List.unmodifiable(scores);
}
