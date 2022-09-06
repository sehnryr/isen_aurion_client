import 'package:isen_aurion_client/isen_aurion_client.dart';

void main(List<String> args) async {
  String serviceUrl = 'https://web.isen-ouest.fr/webAurion/';
  IsenAurionClient client = IsenAurionClient(serviceUrl: serviceUrl);

  // those are example credentials, if you hadn't noticed
  await client.login(
    'username',
    'password',
  );

  var schedule = await client.getUserSchedule();

  // then do whatever you want with that schedule.
  print(schedule);
}
