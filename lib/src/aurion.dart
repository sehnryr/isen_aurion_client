import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:http/http.dart';
import 'package:requests/requests.dart';
import 'package:html/parser.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'package:isen_aurion_client/src/common.dart';
import 'package:isen_aurion_client/src/error.dart';

class IsenAurionClient {
  IsenAurionClient({required this.serviceUrl});

  // The service url
  final String serviceUrl;

  // The viewState string that's attached to the session
  late final String viewState;

  // The form id that's also attached to the session
  late final int formId;

  DateTime get defaultStart {
    var now = DateTime.now();
    var today = DateTime(now.year, now.month, now.day, 0, 0, 0);
    return today.subtract(Duration(days: 1 * 7 + now.weekday));
  }

  DateTime get defaultEnd {
    var now = DateTime.now();
    var endOfYear = DateTime(now.year, 7, 31, 23, 59, 59);
    bool newSchoolYear = now.isAfter(endOfYear);
    var end = DateTime(now.year + (newSchoolYear ? 1 : 0), 7, 31, 23, 59, 59);
    return end.subtract(Duration(days: end.weekday + 1));
  }

  // The whole group tree
  List<Map<String, dynamic>> groupsTree = [];

  /// Get the viewstate value from [response].
  /// Needed for fetching the planning.
  ///
  /// Returns a [String] if found
  ///
  /// Throws a [ParameterNotFound] if not found
  @protected
  String getViewState(Response response) {
    var document = parse(response.content()).documentElement!;
    var result =
        document.queryXPath("//input[@name='javax.faces.ViewState']/@value");

    if (result.attr != null) {
      return result.attr!;
    }
    throw ParameterNotFound(
        "The execution parameter could not be found in the response body.");
  }

  /// Get the viewState value from a request.
  ///
  /// Throws a [ParameterNotFound] if not found.
  @protected
  Future<String> fetchViewState() async {
    Response response = await Requests.get(serviceUrl, withCredentials: true);
    return getViewState(response);
  }

  /// Get the form id from [response].
  /// Needed for doing requests.
  ///
  /// Throws [ParameterNotFound] if the value was not found.
  @protected
  int getFormId(Response response) {
    return int.parse(regexMatch(
        r'chargerSousMenu = function\(\) {PrimeFaces\.ab\({s:"form:j_idt(\d+)"',
        response.content(),
        "The execution parameter could not be found in the response body."));
  }

  /// Get the form id from a request.
  ///
  /// Throws [ParameterNotFound] if the value was not found.
  @protected
  Future<int> fetchFormId() async {
    Response response = await Requests.get(serviceUrl, withCredentials: true);
    return getFormId(response);
  }

  /// Get the submenu [List] from the id. ['submenu_299102'] is the default id
  /// as it is the first id of the groups plannings.
  ///
  /// Throws [ParameterNotFound] if the value couldn't be found.
  Future<List<Map<String, dynamic>>> getSubmenu(
      {String submenuId = 'submenu_299102'}) async {
    String url = "$serviceUrl/faces/MainMenuPage.xhtml";

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

    Response response = await Requests.post(url,
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

    // Set the groups tree every time the initial [getGroupsTree] is called.
    if (!hasParent) {
      groupsTree = tree;
    }

    return tree;
  }

  /// Get a more manageable tree to work with in form of paths like lists where
  /// the furthest item is first and so on to the nearest. The elements of the
  /// [List]s are in reverse order of request
  Future<List<List>> getReadablePaths(
      {String submenuId = 'submenu_299102'}) async {
    List<Map<String, dynamic>> tree = await getSubmenu(submenuId: submenuId);
    return convertTree2Paths(tree: tree);
  }

  /// Converts the groups tree to paths
  List<List> convertTree2Paths({required List<Map> tree}) {
    List<List> paths = [];

    for (var node in tree) {
      Map pathNode = {'name': node['name'], 'id': node['id']};
      if (node.containsKey('children')) {
        List<List> children = convertTree2Paths(tree: node['children']);
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

  /// Get or load the group tree
  Future<List<Map<String, dynamic>>> getOrLoadGroupTree(
      {String submenuId = 'submenu_299102'}) async {
    return groupsTree.isEmpty
        ? await getGroupsTree(submenuId: submenuId)
        : groupsTree;
  }

  /// Get a [List] of the checkboxes before accessing the schedule.
  Future<List<Map<String, dynamic>>> getGroupsSelection(
      {required String groupId, List<Map>? path}) async {
    // return if [groupId] is not in [path]
    if (path != null &&
        path
            .firstWhere((pathNode) => pathNode['id'] == groupId,
                orElse: () => {})
            .isEmpty) {
      print('test');
      return [];
    } else if (path != null &&
        path.isNotEmpty &&
        (groupsTree.isEmpty ||
            convertTree2Paths(tree: groupsTree).contains(path))) {
      path = path.reversed.toList();
      path.removeLast();
      for (var pathNode in path) {
        await getSubmenu();
        await getSubmenu(submenuId: pathNode['id']);
      }
    } else {
      await getOrLoadGroupTree();
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

    String url = '$serviceUrl/faces/MainMenuPage.xhtml';
    Response response = await Requests.post(url,
        queryParameters: payload, withCredentials: true);

    if (!response.headers.containsKey('location')) {
      throw ParameterNotFound(
          'The request might have failed. Has the menu been loaded?');
    }

    response = await Requests.get('$serviceUrl/faces/ChoixPlanning.xhtml',
        withCredentials: true);

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
  Future<List<Map<String, dynamic>>> getSchedule(
      {required String groupId,
      List<Map>? path,
      List<Map>? options,
      DateTime? start,
      DateTime? end}) async {
    options ??= await getGroupsSelection(groupId: groupId, path: path);
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

    Response response = await Requests.get(
        '$serviceUrl/faces/ChoixPlanning.xhtml',
        withCredentials: true);

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
        275805; // French: 275805, English: 251378

    response = await Requests.post('$serviceUrl/faces/ChoixPlanning.xhtml',
        queryParameters: payload, withCredentials: true);

    if (!(response.headers.containsKey('location') &&
            response.statusCode == 302) &&
        RegExp(r"'form:headerSubview:j_idt40'}").hasMatch(response.content())) {
      throw ParameterNotFound('The payload might not be right.');
    }

    if (response.statusCode == 302) {
      response = await Requests.get('$serviceUrl/faces/Planning.xhtml',
          withCredentials: true);
    }
    document = parse(response.content()).documentElement!;

    String defaultParam =
        document.queryXPath('//div[@class="schedule"]/@id').attr!;

    start ??= defaultStart;
    end ??= defaultEnd;

    payload = {
      'javax.faces.partial.ajax': 'true',
      'javax.faces.source': defaultParam,
      'javax.faces.partial.execute': defaultParam,
      'javax.faces.partial.render': defaultParam,
      defaultParam: defaultParam,
      '${defaultParam}_start': start.millisecondsSinceEpoch,
      '${defaultParam}_end': end.millisecondsSinceEpoch,
      'form': 'form',
      'javax.faces.ViewState': getViewState(response),
    };

    response = await Requests.post('$serviceUrl/faces/Planning.xhtml',
        queryParameters: payload, withCredentials: true);

    var events = jsonDecode(regexMatch(
        r'<!\[CDATA\[{"events" : (\[.*?\])}\]\]><\/update>',
        response.content(),
        'Schedule could not be extracted from the body content.'));

    List<Map<String, dynamic>> schedule = [];

    for (var event in events) {
      schedule.add(parseEvent(event));
    }

    return schedule;
  }

  @protected
  Map<String, dynamic> parseEvent(Map<String, dynamic> rawEvent) {
    if (rawEvent.length != 7) {
      return {};
    }

    Map<String, dynamic> event = {
      'id': int.parse(rawEvent['id']),
      'type': rawEvent[
          'className'], // COURS - TP - TD - EVALUATION - REUNION - CONGES
      'start': DateTime.parse(rawEvent['start']).millisecondsSinceEpoch,
      'end': DateTime.parse(rawEvent['end']).millisecondsSinceEpoch,
    };

    String data = rawEvent['title'];
    // https://regex101.com/r/xfG2EU/1
    var result = RegExp(r'((?:(?<= - )|^)(?:(?! - ).)*?)(?: - |$)')
        .allMatches(data)
        .toList();

    if (RegExp(r'\d\dh\d\d - \d\dh\d\d').hasMatch(data)) {
      event['room'] = result[6].group(1)!;
      event['subject'] = result[3].group(1)!;
      event['chapter'] = result[4].group(1)!;
      event['participants'] = result[5].group(1)!.split(' / ');
    } else {
      event['room'] = result[1].group(1)!;
      event['subject'] = result[3].group(1)!;
      event['chapter'] = result[4].group(1)!;
      event['participants'] = result[5].group(1)!.split(' / ');
    }

    return event;
  }

  Future<List<Map<String, dynamic>>> getUserSchedule({
    DateTime? start,
    DateTime? end,
  }) async {
    await getSubmenu(submenuId: 'submenu_291906'); // Schooling submenu

    Map<String, dynamic> payload = {
      'form': 'form',
      'form:sauvegarde': null,
      'form:largeurDivCenter': null,
      'form:j_idt820_focus': null,
      'form:j_idt820_input': null,
      'form:sidebar': 'form:sidebar',
      'form:j_idt805:j_idt808_view': 'basicDay',
      'javax.faces.ViewState': viewState,
      'form:sidebar_menuid': '1_3'
    };

    Response response = await Requests.post(
        '$serviceUrl/faces/MainMenuPage.xhtml',
        queryParameters: payload,
        withCredentials: true);

    if (!(response.headers.containsKey('location') &&
            response.statusCode == 302) &&
        !RegExp(r"<title>Mon planning").hasMatch(response.content())) {
      throw ParameterNotFound('The payload might not be right.');
    }

    if (response.statusCode == 302) {
      response = await Requests.get('$serviceUrl/faces/Planning.xhtml',
          withCredentials: true);
    }
    var document = parse(response.content()).documentElement!;

    String defaultParam =
        document.queryXPath('//div[@class="schedule"]/@id').attr!;

    start ??= defaultStart;
    end ??= defaultEnd;

    payload = {
      'javax.faces.partial.ajax': 'true',
      'javax.faces.source': defaultParam,
      'javax.faces.partial.execute': defaultParam,
      'javax.faces.partial.render': defaultParam,
      defaultParam: defaultParam,
      '${defaultParam}_start': start.millisecondsSinceEpoch,
      '${defaultParam}_end': end.millisecondsSinceEpoch,
      'form': 'form',
      'javax.faces.ViewState': getViewState(response),
    };

    response = await Requests.post('$serviceUrl/faces/Planning.xhtml',
        queryParameters: payload, withCredentials: true);

    var events = jsonDecode(regexMatch(
        r'<!\[CDATA\[{"events" : (\[.*?\])}\]\]><\/update>',
        response.content(),
        'Schedule could not be extracted from the body content.'));

    List<Map<String, dynamic>> schedule = [];

    for (var event in events) {
      schedule.add(parseEvent(event));
    }

    return schedule;
  }

  /// Login to Aurion with [username] and [password] by storing the connection
  /// cookie with [Requests].
  ///
  /// Throws and [AuthenticationException] if one of the credentials is wrong.
  Future<void> login(String username, String password) async {
    String loginUrl = "$serviceUrl/login";

    Response response = await Requests.post(loginUrl,
        body: {'username': username, 'password': password},
        withCredentials: true);

    if (!response.headers.containsKey('location') &&
        !RegExp(r"<title>Page d'accueil").hasMatch(response.content())) {
      throw AuthenticationException('The username or password might be wrong.');
    }

    // Retrieve the session attached variables
    Response dummyResponse =
        await Requests.get(serviceUrl, withCredentials: true);

    viewState = getViewState(dummyResponse);
    formId = getFormId(dummyResponse);
  }
}
