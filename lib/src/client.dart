import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:http/http.dart';
import 'package:requests/requests.dart';
import 'package:html/parser.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'package:isen_aurion_client/src/common.dart';
import 'package:isen_aurion_client/src/config.dart';
import 'package:isen_aurion_client/src/error.dart';
import 'package:isen_aurion_client/src/event.dart';
import 'package:isen_aurion_client/src/pages.dart';

class IsenAurionClient {
  factory IsenAurionClient({required String serviceUrl}) {
    return IsenAurionClient._internal(Pages(serviceUrl));
  }

  IsenAurionClient._internal(this.pages);

  // The pages of the Aurion website
  final Pages pages;

  // The service url
  String get serviceUrl => pages.serviceUrl;

  // The viewState string that's attached to the session
  late final String viewState;

  // The form id that's also attached to the session
  late final int formId;

  DateTime get defaultStart => Config.defaultStart;

  DateTime get defaultEnd => Config.defaultEnd;

  /// Get the viewstate value from [response].
  /// Needed for fetching the planning.
  ///
  /// Returns a [String] if found
  ///
  /// Throws a [ParameterNotFound] if not found
  @protected
  String getViewState(Response response) {
    var viewState = extractViewState(response);
    if (viewState == null) {
      throw ParameterNotFound('ViewState could not be found.');
    }
    return viewState;
  }

  /// Extract the viewState value from the [response] body.
  /// Needed for fetching the planning.
  @protected
  String? extractViewState(Response response) {
    var content = response.content();
    var splitter = 'name="javax.faces.ViewState"';
    if (content.contains(splitter)) {
      return content.split(splitter)[1].split('value="')[1].split('"')[0];
    }
    return null;
  }

  /// Get the form id from [response].
  /// Needed for doing requests.
  ///
  /// Throws [ParameterNotFound] if the value was not found.
  @protected
  int getFormId(Response response) {
    var formId = extractFormId(response);
    if (formId == null) {
      throw ParameterNotFound('FormId could not be found.');
    }
    return formId;
  }

  /// Extract the form id from the [response] body.
  /// Needed for doing requests.
  @protected
  int? extractFormId(Response response) {
    var content = response.content();
    var splitter = 'chargerSousMenu = function() {PrimeFaces.ab({s:"form:j_idt';
    if (content.contains(splitter)) {
      return int.parse(content.split(splitter)[1].split('"')[0]);
    }
    return null;
  }

  /// Get the schedule form id from [response].
  /// Needed for fetching the planning.
  ///
  /// Throws [ParameterNotFound] if the value was not found.
  @protected
  int getScheduleFormId(Response response) {
    var formId = extractScheduleFormId(response);
    if (formId == null) {
      throw ParameterNotFound('UserScheduleFormId could not be found.');
    }
    return formId;
  }

  /// Extract the schedule form id from the [response] body.
  /// Needed for fetching the planning.
  @protected
  int? extractScheduleFormId(Response response) {
    var content = response.content();
    var splitter = '" class="schedule"';
    if (content.contains(splitter)) {
      return int.parse(content.split(splitter)[0].split('id="form:j_idt').last);
    }
    return null;
  }

  /// Get the submenu [List] from the id. ['submenu_299102'] is the default id
  /// as it is the first id of the groups plannings.
  ///
  /// Throws [ParameterNotFound] if the value couldn't be found.
  Future<List<Map<String, dynamic>>> getSubmenu(
      {String submenuId = 'submenu_299102'}) async {
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

    Response response = await Requests.post(pages.mainMenuUrl,
        queryParameters: payload, withCredentials: true);

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

  /// Get the whole menu tree recursively. It takes around 20sec to make it.
  Future<List<Map<String, dynamic>>> getGroupsTree(
      {String submenuId = 'submenu_299102', bool hasParent = false}) async {
    List<Map<String, dynamic>> tree = await getSubmenu(submenuId: submenuId);

    for (var child in tree) {
      if (child.containsKey('children')) {
        String id = child['id'];
        child['children'] = await getGroupsTree(submenuId: id, hasParent: true);
      }
    }

    return tree;
  }

  /// Get a more manageable tree to work with in form of paths like lists where
  /// the furthest item is first and so on to the nearest. The elements of the
  /// [List]s are in reverse order of request
  Future<List<List>> getReadablePaths(
      {String submenuId = 'submenu_299102'}) async {
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
    String submenuId = 'submenu_299102',
  }) async {
    if (path != null) {
      // return if [groupId] is not in [path]
      if (!path.any((pathNode) => pathNode['id'] == groupId)) {
        return [];
      } else if (path.isNotEmpty) {
        path = path.reversed.toList();
        path.removeLast();
        for (var pathNode in path) {
          await getSubmenu(submenuId: pathNode['id']);
        }
      }
    } else {
      var groupsTree = await getGroupsTree(submenuId: submenuId);

      // return if [groupId] is not in [groupsTree]
      bool pathExist = convertTree2Paths(tree: groupsTree)
          .any((path) => path.any((pathNode) => pathNode['id'] == groupId));
      if (!pathExist) {
        return [];
      }
    }

    Map<String, dynamic> payload = {
      'form': 'form',
      'form:sauvegarde': null,
      'form:largeurDivCenter': null,
      'form:j_idt820_focus': null,
      'form:j_idt820_input': null,
      'form:sidebar': 'form:sidebar',
      'form:j_idt805:j_idt808_view': 'basicDay',
      'javax.faces.ViewState': viewState,
      'form:sidebar_menuid': groupId
    };

    Response response = await Requests.post(pages.mainMenuUrl,
        queryParameters: payload, withCredentials: true);

    if (!response.headers.containsKey('location')) {
      throw ParameterNotFound(
          'The request might have failed. Has the menu been loaded?');
    }

    response =
        await Requests.get(pages.planningChoiceUrl, withCredentials: true);

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

  /// Get the schedule with all the options checked by default.
  ///
  /// Throws [ParameterNotFound] if Aurion's schedule is not in the
  /// expected format.
  Future<List<Event>> getSchedule({
    required String groupId,
    List<Map>? path,
    List<Map>? options,
    DateTime? start,
    DateTime? end,
    String submenuId = 'submenu_299102',
    int languageCode = 275805, // French: 275805, English: 251378 for ISEN Ouest
  }) async {
    options ??= await getGroupsSelection(
      groupId: groupId,
      path: path,
      submenuId: submenuId,
    );
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
    };

    Response response =
        await Requests.get(pages.planningChoiceUrl, withCredentials: true);

    payload['javax.faces.ViewState'] = getViewState(response);

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
        languageCode;

    response = await Requests.post(pages.planningChoiceUrl,
        queryParameters: payload, withCredentials: true);

    if (!(response.headers.containsKey('location') &&
            response.statusCode == 302) &&
        RegExp(r"'form:headerSubview:j_idt40'}").hasMatch(response.content())) {
      throw ParameterNotFound('The payload might not be right.');
    }

    if (response.statusCode == 302) {
      response = await Requests.get(pages.planningUrl, withCredentials: true);
    }

    int scheduleFormId = getScheduleFormId(response);

    start ??= defaultStart;
    end ??= defaultEnd;

    payload = {
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

    response = await Requests.post(pages.planningUrl,
        queryParameters: payload, withCredentials: true);

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

  /// Get the user's schedule with all the options checked by default.
  ///
  /// Throws [ParameterNotFound] if Aurion's schedule is not in the
  /// expected format.
  Future<List<Event>> getUserSchedule({
    String submenuId = 'submenu_291906',
    String submenuItemId = '1_3', // form:sidebar_menuid
    DateTime? start,
    DateTime? end,
  }) async {
    await getSubmenu(submenuId: submenuId); // Schooling submenu

    Map<String, dynamic> payload = {
      'form': 'form',
      'form:sauvegarde': null,
      'form:largeurDivCenter': null,
      'form:j_idt820_focus': null,
      'form:j_idt820_input': null,
      'form:sidebar': 'form:sidebar',
      'form:j_idt805:j_idt808_view': 'basicDay',
      'javax.faces.ViewState': viewState,
      'form:sidebar_menuid': submenuItemId,
    };

    Response response = await Requests.post(pages.mainMenuUrl,
        queryParameters: payload, withCredentials: true);

    if (!(response.headers.containsKey('location') &&
            response.statusCode == 302) &&
        !RegExp(r"<title>Mon planning").hasMatch(response.content())) {
      throw ParameterNotFound('The payload might not be right.');
    }

    if (response.statusCode == 302) {
      response = await Requests.get(pages.planningUrl, withCredentials: true);
    }

    int scheduleFormId = getScheduleFormId(response);

    start ??= defaultStart;
    end ??= defaultEnd;

    payload = {
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

    response = await Requests.post(pages.planningUrl,
        queryParameters: payload, withCredentials: true);

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

  /// Login to Aurion with [username] and [password] by storing the connection
  /// cookie with [Requests].
  ///
  /// Throws and [AuthenticationException] if one of the credentials is wrong.
  Future<void> login(String username, String password) async {
    String loginUrl = pages.loginUrl;

    Response response = await Requests.post(loginUrl,
        body: {'username': username, 'password': password},
        withCredentials: true);

    if (!response.headers.containsKey('location') &&
        !RegExp(r"<title>Page d'accueil").hasMatch(response.content())) {
      throw AuthenticationException('The username or password might be wrong.');
    }

    // Retrieve the session attached variables
    Response dummyResponse =
        await Requests.get(pages.serviceUrl, withCredentials: true);

    viewState = getViewState(dummyResponse);
    formId = getFormId(dummyResponse);
  }
}
