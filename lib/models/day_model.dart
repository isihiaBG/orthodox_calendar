class CalendarDay {
  final String date;
  final int tone;
  final int fastType;
  final int fastPeriod;
  final int? weekId;
  final int? sundayId;
  final String? weekName;
  final String? weekNote;
  final String? sundayName;
  final String? sundayNote;

  CalendarDay({
    required this.date,
    required this.tone,
    required this.fastType,
    required this.fastPeriod,
    this.weekId,
    this.sundayId,
    this.weekName,
    this.weekNote,
    this.sundayName,
    this.sundayNote,
  });

  factory CalendarDay.fromMap(Map<String, dynamic> map) {
    return CalendarDay(
      date: map['date'],
      tone: map['tone'] ?? 0,
      fastType: map['fast_type'] ?? 0,
      fastPeriod: map['fast_period'] ?? 0,
      weekId: map['week_id'],
      sundayId: map['sunday_id'],
      weekName: map['week_name'],
      weekNote: map['week_note'],
      sundayName: map['sunday_name'],
      sundayNote: map['sunday_note'],
    );
  }

  // Връща пълното наименование на неделята
  String? get fullSundayName {
    if (sundayName == null) return null;
    if (sundayNote == null || sundayNote!.isEmpty) return sundayName;
    return '$sundayName, $sundayNote';
  }
  
  // Връща пълното наименование на седмицата
  String? get fullWeekName {
  if (weekName == null) return null;
  if (weekNote == null || weekNote!.isEmpty) return weekName;
  return '$weekName. $weekNote';
  }

}

class Saint {
  final int id;
  final String date;
  final String name;
  final int rank;
  final String? sign;
  final String? signColor;
  final bool hasTropar;
  final bool hasKondak;
  final bool hasLife;
  final bool hasSluzhba;
  

  Saint({
    required this.id,
    required this.date,
    required this.name,
    required this.rank,
    this.sign,
    this.signColor,
    this.hasTropar  = false,
    this.hasKondak  = false,
    this.hasLife    = false,
    this.hasSluzhba = false,
  });

  factory Saint.fromMap(Map<String, dynamic> map) {
    return Saint(
      id: map['id'],
      date: map['date'],
      name: map['name'],
      rank: map['rank'] ?? 4,
      sign: map['sign'],
      signColor: map['sign_color'],
      hasTropar:  (map['has_tropar']  ?? 0) == 1,
      hasKondak:  (map['has_kondak']  ?? 0) == 1,
      hasLife:    (map['has_life']    ?? 0) == 1,
      hasSluzhba: (map['has_sluzhba'] ?? 0) == 1,
    );
  }
}
