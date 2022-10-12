import 'package:http/http.dart';
import 'package:requests/requests.dart';

extension ResponseExtension on Response {
  String? get viewState {
    var content = this.content();
    var splitter = 'name="javax.faces.ViewState"';
    if (content.contains(splitter)) {
      return content.split(splitter)[1].split('value="')[1].split('"')[0];
    }
    return null;
  }

  int? get formId {
    var content = this.content();
    var splitter = 'chargerSousMenu = function() {PrimeFaces.ab({s:"form:j_idt';
    if (content.contains(splitter)) {
      return int.parse(content.split(splitter)[1].split('"')[0]);
    }
    return null;
  }

  int? get scheduleFormId {
    var content = this.content();
    var splitter = '" class="schedule"';
    if (content.contains(splitter)) {
      return int.parse(content.split(splitter)[0].split('id="form:j_idt').last);
    }
    return null;
  }
}
