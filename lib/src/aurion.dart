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
    Response response = await Requests.get(serviceUrl);
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
    Response response = await Requests.get(serviceUrl);
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

    Response response = await Requests.post(url, queryParameters: payload);

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

  Future<List<Map<String, dynamic>>> getGroupsTree(
      {String submenuId = 'submenu_299102'}) async {
    List<Map<String, dynamic>> tree = await getSubmenu(submenuId: submenuId);

    for (var child in tree) {
      if (child.containsKey('children')) {
        String id = child['id'];
        print(id);
        child['children'] = await getGroupsTree(submenuId: id);
      }
    }

    return tree;
  }

  /// Login to Aurion with [username] and [password] by storing the connection
  /// cookie with [Requests].
  ///
  /// Throws and [AuthenticationException] if one of the credentials is wrong.
  Future<void> login(String username, String password) async {
    String loginUrl = "$serviceUrl/login";

    Response response = await Requests.post(loginUrl,
        body: {'username': username, 'password': password});

    if (!response.headers.containsKey('location')) {
      throw AuthenticationException('The username or password might be wrong.');
    }

    // Retrieve the session attached variables
    Response dummyResponse = await Requests.get(serviceUrl);

    viewState = getViewState(dummyResponse);
    formId = getFormId(dummyResponse);
  }
}
