/// Two vocabularies in one library, as parts: what they share (a record's
/// shape) is made once, in the index's `.g.dart`.
library;

import 'package:parlance/schema.dart';

part 'doors.dart';
part 'lights.dart';
part '_index.g.dart';

/// A room, as both vocabularies carry it.
typedef Room = ({@Describe('Its name.') String name, int floor});
