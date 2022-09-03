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

  Future<void> getGroups() async {
    String url = "$serviceUrl/faces/MainMenuPage.xhtml";
    String submenuId = 'submenu_299102'; // Groups submenuId on Aurion

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

    String rawGroups = regexMatch(
        '$submenuId[^>]+>(?:<[^>]+>)*[^<]+(?:<[^>]+>){5}(.+?)</ul>',
        response.content(),
        "The execution parameter could not be found in the response body.");

    var pattern =
        RegExp(r'<li[^>]+(submenu_\d+).+?<span[^>]+ui-menuitem-text">([^<]+)');
    Iterable<RegExpMatch> matches = pattern.allMatches(rawGroups);
    List<Map<String, String>> groups = [];

    for (var match in matches) {
      var groupId = match.group(1);
      var groupName = match.group(2);

      if (groupId != null && groupName != null) {
        groups.add({
          'id': groupId,
          'name': groupName.replaceAll(RegExp(r'Plannings'), '').trim()
        });
      }
    }

    print(groups);
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
