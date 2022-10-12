import 'package:isen_aurion_client/client.dart';

void main(List<String> args) async {
  String serviceUrl = 'https://web.isen-ouest.fr/webAurion/';
  AurionClient client = AurionClient(
    serviceUrl: serviceUrl,
    languageCode: 275805,
    schoolingId: 'submenu_291906',
    userPlanningId: '1_3',
    groupsPlanningsId: 'submenu_299102',
  );

  // those are example credentials, if you hadn't noticed
  await client.login(
    'username',
    'password',
  );

  var schedule = await client.getUserSchedule();

  // then do whatever you want with that schedule.
  print(schedule);
}
