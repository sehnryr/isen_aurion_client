class AurionMenu {
  int languageCode;
  String schoolingId;
  String userPlanningId; // child of [schoolingId]
  String groupsPlanningsId;

  AurionMenu({
    required this.languageCode,
    required this.schoolingId,
    required this.userPlanningId,
    required this.groupsPlanningsId,
  });

  List<List<Map>> menus = []; // the path to the furthest menu item
}
