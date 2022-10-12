import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:http/http.dart';
import 'package:requests/requests.dart';
import 'package:html/parser.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'package:isen_aurion_client/src/aurion_menu.dart';
import 'package:isen_aurion_client/src/aurion_pages.dart';
import 'package:isen_aurion_client/src/common.dart';
import 'package:isen_aurion_client/src/config.dart';
import 'package:isen_aurion_client/src/error.dart';
import 'package:isen_aurion_client/src/event.dart';
import 'package:isen_aurion_client/src/response.dart';

class IsenAurionClient {
  factory IsenAurionClient({
    required int languageCode,
    required String schoolingId,
    required String userPlanningId,
    required String groupsPlanningsId,
    required String serviceUrl,
  }) {
    return IsenAurionClient._internal(
      AurionMenu(
          languageCode: languageCode,
          schoolingId: schoolingId,
          userPlanningId: userPlanningId,
          groupsPlanningsId: groupsPlanningsId),
      AurionPages(serviceUrl),
    );
  }

  IsenAurionClient._internal(this.menu, this.pages);

  // The ids of the menus
  final AurionMenu menu;

  // The pages of the Aurion website
  final AurionPages pages;

  // The service url
  String get serviceUrl => pages.serviceUrl;

  // The viewState string that's attached to the session
  late final String viewState;

  // The form id that's also attached to the session
  late final int formId;

  DateTime get defaultStart => Config.defaultStart;
  DateTime get defaultEnd => Config.defaultEnd;

  // List of all the loaded paths
  List<List<Map>> get paths => menu.menus;
  set paths(List<List<Map>> value) => menu.menus = value;

  Map<String, dynamic> defaultParameters({required String menuId}) {
    // this payload form ids seems to be constant (805, 808, 820).
    return {
      'form': 'form',
      'form:sauvegarde': null,
      'form:largeurDivCenter': null,
      'form:j_idt820_focus': null,
      'form:j_idt820_input': null,
      'form:sidebar': 'form:sidebar',
      'form:j_idt805:j_idt808_view': 'basicDay',
      'javax.faces.ViewState': viewState,
      'form:sidebar_menuid': menuId
    };
  }

  /// Get the viewstate value from [response].
  /// Needed for fetching the planning.
  ///
  /// Throws a [ParameterNotFound] if not found
  @protected
  String getViewState(Response response) {
    var viewState = response.viewState;
    if (viewState == null) {
      throw ParameterNotFound('ViewState could not be found.');
    }
    return viewState;
  }

  /// Get the form id from [response].
  /// Needed for doing requests.
  ///
  /// Throws [ParameterNotFound] if the value was not found.
  @protected
  int getFormId(Response response) {
    var formId = response.formId;
    if (formId == null) {
      throw ParameterNotFound('FormId could not be found.');
    }
    return formId;
  }

  /// Get the schedule form id from [response].
  /// Needed for fetching the planning.
  ///
  /// Throws [ParameterNotFound] if the value was not found.
  @protected
  int getScheduleFormId(Response response) {
    var formId = response.scheduleFormId;
    if (formId == null) {
      throw ParameterNotFound('ScheduleFormId could not be found.');
    }
    return formId;
  }

  /// Get the submenu [List] from the id.
  ///
  /// Throws [ParameterNotFound] if the value couldn't be found.
  Future<List<Map<String, dynamic>>> getSubmenu({
    required String submenuId,
  }) async {
    Map<String, dynamic> payload = {
      'javax.faces.partial.ajax': true,
      'javax.faces.source': 'form:j_idt$formId',
      'javax.faces.partial.execute': 'form:j_idt$formId',
      'javax.faces.partial.render': 'form:sidebar',
      'form:j_idt$formId': 'form:j_idt$formId',
      'form': 'form',
      'form:largeurDivCenter': null,
      'form:sauvegarde': null,
      'form:j_idt805:j_idt808_view': 'basicDay',
      'form:j_idt820_focus': null,
      'form:j_idt820_input': null,
      'javax.faces.ViewState': viewState,
      'webscolaapp.Sidebar.ID_SUBMENU': submenuId
    };

    Response response = await Requests.post(
      pages.mainMenuUrl,
      queryParameters: payload,
      withCredentials: true,
    );

    String data = regexMatch(
        r'<update id="form:sidebar"><!\[CDATA\[(.*?)\]\]>',
        response.content(),
        "The content of the update could not be found in the response body.");

    var document = parse(data).documentElement!;
    var result =
        document.queryXPath('//li[contains(@class, "$submenuId")]/ul/li');

    List<Map<String, dynamic>> submenus = [];

    for (var node in result.nodes) {
      Map attributes = node.attributes;
      bool isParent = attributes['class'].contains('ui-menu-parent');
      String name = node
          .queryXPath('/a/span[@class="ui-menuitem-text"]/text()')
          .attr!
          .replaceAll(RegExp(r'Plannings?'), '')
          .trim();

      Map<String, dynamic> entry = {'name': name};

      if (isParent) {
        entry['id'] =
            RegExp(r'(submenu_\d+)').firstMatch(attributes['class'])!.group(1)!;
        entry['children'] = [];
      } else {
        entry['id'] = RegExp(r"form:sidebar_menuid':'([^']+)")
            .firstMatch(node.queryXPath('/a/@onclick').attr!)!
            .group(1)!;
      }

      submenus.add(entry);
    }

    return submenus;
  }

  /// Get the path for a given [groupId].
  ///
  /// Return `null` if not found.
  List<Map>? getPath(String groupId) {
    var path = paths.firstWhere((element) => element[0]['id'] == groupId,
        orElse: () => []);
    return path.isNotEmpty ? path : null;
  }

  /// Check if the [path] is loaded or not
  bool isPathLoaded(List<Map> path) {
    return paths.any((element) {
      if (element.length != path.length) return false;
      for (int i = 0; i < element.length; i++) {
        if (element[i]['id'] != path[i]['id']) {
          return false;
        }
      }
      return true;
    });
  }

  /// Load the path for accessing Aurion.
  ///
  /// Example:
  /// ```
  /// [
  ///   {'name': 'CIR 2', 'id': '2_6_2_1'},
  ///   {'name': 'CIR Nantes', 'id': 'submenu_2853538'},
  ///   {'name': 'CIR', 'id': 'submenu_299116'},
  ///   {'name': 'Groups', 'id': 'submenu_299102'},
  /// ]
  /// ```
  Future<void> loadPath(List<Map> path) async {
    if (path.isNotEmpty &&
        !path.any((pathNode) => !pathNode.containsKey('id')) &&
        getPath(path[0]['id']) == null) {
      var normalPath = path.reversed.toList();
      normalPath.removeLast();
      for (var pathNode in normalPath) {
        await getSubmenu(submenuId: pathNode['id']);
      }
      paths.add(path);
    }
  }

  /// Get the whole menu tree recursively. It takes around 20sec to make it.
  Future<List<Map<String, dynamic>>> getGroupsTree({
    required String submenuId,
    bool hasParent = false,
  }) async {
    List<Map<String, dynamic>> tree = await getSubmenu(submenuId: submenuId);

    for (var child in tree) {
      if (child.containsKey('children')) {
        String id = child['id'];
        child['children'] = await getGroupsTree(submenuId: id, hasParent: true);
      }
    }

    paths = convertTree2Paths(tree: tree);
    return tree;
  }

  /// Get a more manageable tree to work with in form of paths like lists where
  /// the furthest item is first and so on to the nearest. The elements of the
  /// [List]s are in reverse order of request
  Future<List<List>> getReadablePaths({required String submenuId}) async {
    List<Map<String, dynamic>> tree = await getGroupsTree(submenuId: submenuId);
    return convertTree2Paths(tree: tree);
  }

  /// Converts the groups tree to paths
  List<List<Map>> convertTree2Paths({required List<Map> tree}) {
    List<List<Map>> paths = [];

    for (var node in tree) {
      Map pathNode = {'name': node['name'], 'id': node['id']};
      if (node.containsKey('children')) {
        List<List<Map>> children = convertTree2Paths(tree: node['children']);
        for (var child in children) {
          child.add(pathNode);
          paths.add(child);
        }
      } else {
        paths.add([pathNode]);
      }
    }

    return paths;
  }

  /// Get a [List] of the checkboxes before accessing the schedule.
  Future<List<Map<String, dynamic>>> getGroupsSelection({
    required String groupId,
    List<Map>? path,
  }) async {
    if (path != null) {
      // return if [groupId] is not in [path]
      if (!path.any((pathNode) => pathNode['id'] == groupId)) {
        return [];
      } else if (!isPathLoaded(path)) {
        await loadPath(path);
      }
    } else if (getPath(groupId) != null) {
    } else {
      await getGroupsTree(submenuId: menu.groupsPlanningsId);

      // return if [groupId] is not in [paths]
      if (!paths.any((element) => element[0]['id'] == groupId)) {
        return [];
      }
    }

    Response response = await Requests.post(
      pages.mainMenuUrl,
      queryParameters: defaultParameters(menuId: groupId),
      withCredentials: true,
    );

    if (!response.headers.containsKey('location')) {
      throw ParameterNotFound(
          'The request might have failed. Has the menu been loaded?');
    }

    response = await Requests.get(
      pages.planningChoiceUrl,
      withCredentials: true,
    );

    var document = parse(response.content()).documentElement!;

    var selectionOptions =
        document.queryXPath('//div[@id="form:dataTableFavori"]//tbody/tr');

    List<Map<String, dynamic>> options = [];

    for (var element in selectionOptions.nodes) {
      String id = element.attributes['data-rk']!;
      String name = element
          .queryXPath('//span[contains(@class, "preformatted")]/text()')
          .attr!;

      options.add({'id': id, 'name': name});
    }

    return options;
  }

  /// Get the schedule from [response].
  /// Used by [getSgetGroupSchedulechedule] and [getUserSchedule].
  @protected
  Future<List<Event>> getSchedule({
    required Response response,
    DateTime? start,
    DateTime? end,
  }) async {
    response = await Requests.get(
      pages.planningUrl,
      withCredentials: true,
    );

    int scheduleFormId = getScheduleFormId(response);

    start ??= defaultStart;
    end ??= defaultEnd;

    var payload = {
      'javax.faces.partial.ajax': 'true',
      'javax.faces.source': 'form:j_idt$scheduleFormId',
      'javax.faces.partial.execute': 'form:j_idt$scheduleFormId',
      'javax.faces.partial.render': 'form:j_idt$scheduleFormId',
      'form:j_idt$scheduleFormId': 'form:j_idt$scheduleFormId',
      'form:j_idt${scheduleFormId}_start': start.millisecondsSinceEpoch,
      'form:j_idt${scheduleFormId}_end': end.millisecondsSinceEpoch,
      'form': 'form',
      'javax.faces.ViewState': getViewState(response),
    };

    response = await Requests.post(
      pages.planningUrl,
      queryParameters: payload,
      withCredentials: true,
    );

    var eventsJson = jsonDecode(regexMatch(
        r'<!\[CDATA\[{"events" : (\[.*?\])}\]\]><\/update>',
        response.content(),
        'Schedule could not be extracted from the body content.'));

    List<Event> schedule = [];

    for (var eventJson in eventsJson) {
      schedule.add(parseEvent(eventJson));
    }

    return schedule;
  }

  /// Get the schedule with all the options checked by default.
  ///
  /// Throws [ParameterNotFound] if Aurion's schedule is not in the
  /// expected format.
  ///
  /// When setting [options], [path] must be set as well.
  Future<List<Event>> getGroupSchedule({
    required String groupId,
    List<Map>? path,
    List<Map>? options,
    DateTime? start,
    DateTime? end,
  }) async {
    // get the group options if [options] is null
    options ??= await getGroupsSelection(
      groupId: groupId,
      path: path,
    );

    // either [path] or the groups tree must be loaded before doing this request
    // used to get the viewState
    Response response = await Requests.get(
      pages.planningChoiceUrl,
      withCredentials: true,
    );

    // format the options to be sent in the request in the payload
    String selection = options.map((e) => e['id']).join(',');

    var payload = {
      'form': 'form',
      'form:largeurDivCenter': 100, // can't be less than 100
      'form:messagesRubriqueInaccessible': null,
      'form:search-texte': null,
      'form:search-texte-avancer': null,
      'form:input-expression-exacte': null,
      'form:input-un-des-mots': null,
      'form:input-aucun-des-mots': null,
      'form:input-nombre-debut': null,
      'form:input-nombre-fin': null,
      'form:calendarDebut_input': null,
      'form:calendarFin_input': null,
      'javax.faces.ViewState': getViewState(response),
    };

    var document = parse(response.content()).documentElement!;
    var result = document.queryXPath(
        '//div[@id="form:dataTableFavori"]//*[starts-with(@name, "form:j_idt")]/@name');

    for (var element in result.attrs) {
      String name = element!;
      if (element.endsWith('reflowDD')) {
        payload[name] = '0_0';
      } else if (element.endsWith('selection')) {
        payload[name] = selection;
      } else if (element.endsWith('filter')) {
        payload[name] = null;
      } else if (element.endsWith('checkbox')) {
        payload[name] = List.generate(options.length, (_) => 'on');
      }
    }

    result =
        document.queryXPath('//div[@id="form:footerToolBar"]/button/@name');
    payload[result.attr!] = null;

    result = document.queryXPath(
        '//div[@class="listeLangues"]//input[starts-with(@name, "form")]/@name');
    payload[result.attr!] = null;
    payload[result.attr!.replaceFirst(RegExp(r'_focus$'), '_input')] =
        menu.languageCode;

    response = await Requests.post(
      pages.planningChoiceUrl,
      queryParameters: payload,
      withCredentials: true,
    );

    // If the request was no correctly redirected and the page is not
    // the expected one, throw an error.
    if (!(response.headers.containsKey('location') &&
            response.statusCode == 302) &&
        RegExp(r"'form:headerSubview:j_idt40'}").hasMatch(response.content())) {
      throw ParameterNotFound('The payload might not be right.');
    }

    return getSchedule(
      response: response,
      start: start,
      end: end,
    );
  }

  /// Get the user's schedule with all the options checked by default.
  ///
  /// Throws [ParameterNotFound] if Aurion's schedule is not in the
  /// expected format.
  Future<List<Event>> getUserSchedule({
    DateTime? start,
    DateTime? end,
  }) async {
    if (getPath(menu.schoolingId) == null) {
      await getSubmenu(submenuId: menu.schoolingId); // Schooling submenu
      paths.add([
        {'id': menu.schoolingId, 'name': 'Schooling'}
      ]);
    }

    Response response = await Requests.post(
      pages.mainMenuUrl,
      queryParameters: defaultParameters(menuId: menu.userPlanningId),
      withCredentials: true,
    );

    // If the request was no correctly redirected and the page is not
    // the expected one, throw an error.
    if (!(response.headers.containsKey('location') &&
            response.statusCode == 302) &&
        !RegExp(r"<title>Mon planning").hasMatch(response.content())) {
      throw ParameterNotFound('The payload might not be right.');
    }

    return getSchedule(
      response: response,
      start: start,
      end: end,
    );
  }

  /// Login to Aurion with [username] and [password] by storing the connection
  /// cookie with [Requests].
  ///
  /// Throws and [AuthenticationException] if one of the credentials is wrong.
  Future<void> login(String username, String password) async {
    String loginUrl = pages.loginUrl;

    Response response = await Requests.post(
      loginUrl,
      body: {'username': username, 'password': password},
      withCredentials: true,
    );

    if (!response.headers.containsKey('location') &&
        !RegExp(r"<title>Page d'accueil").hasMatch(response.content())) {
      throw AuthenticationException('The username or password might be wrong.');
    }

    // Retrieve the session attached variables
    Response dummyResponse = await Requests.get(
      pages.serviceUrl,
      withCredentials: true,
    );

    viewState = getViewState(dummyResponse);
    formId = getFormId(dummyResponse);
  }
}
