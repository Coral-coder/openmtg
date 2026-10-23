import 'package:rules/rules.dart';

void main(List<String> args) {
  for (final t in args) {
    OracleParser.diag = [];
    final a = OracleParser.parseGranted(t);
    print('${a == null ? 'FAIL' : 'ok  '} $t ${a == null ? OracleParser.diag : describeAbility(a)}');
  }
}
