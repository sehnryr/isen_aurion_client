class Pages {
  final String _serviceUrl;

  Pages(this._serviceUrl);

  String get loginUrl => '$serviceUrl/login';
  String get mainMenuUrl => '$serviceUrl/faces/MainMenuPage.xhtml';
  String get planningChoiceUrl => '$serviceUrl/faces/ChoixPlanning.xhtml';
  String get planningUrl => '$serviceUrl/faces/Planning.xhtml';
  String get serviceUrl => _serviceUrl;
}
