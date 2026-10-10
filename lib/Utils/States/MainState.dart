import 'package:scoped_model/scoped_model.dart';
import 'package:sanqian_class/Utils/States/ConfigState.dart';
import './ClassTableState.dart';
import './ThemeState.dart';
import './WeekState.dart';
import './FlagState.dart';

class MainStateModel extends Model
    with
        ThemeStateModel,
        ClassTableStateModel,
        WeekStateModel,
        FlagStateModel,
        ConfigStateModel {
  static MainStateModel of(context) =>
      ScopedModel.of<MainStateModel>(context, rebuildOnChange: true);
}
