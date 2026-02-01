import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';
import '../../domain/standings/standings.dart';

/// A sortable, scrollable standings table rendered using the [StandingsRow] model.
///
/// - Horizontally scrollable for narrow screens.
/// - Vertically scrollable when there are many teams.
/// - Sortable by tapping column headers.
/// - Allows optional custom row coloring via [rowColorBuilder].
class StandingsTable extends StatefulWidget {
  const StandingsTable({
    super.key,
    required this.rows,
    this.rowColorBuilder,
  });

  /// Raw, unsorted list of standing rows.
  final List<StandingsRow> rows;

  /// Optional custom row color function.
  ///
  /// Parameters:
  /// - [context]: BuildContext
  /// - [index]: 0-based index in the sorted table
  /// - [row]: the actual [StandingsRow] for that index
  /// - [total]: total number of rows
  ///
  /// Return a [Color] to tint the row, or null for no background.
  final Color? Function(
    BuildContext context,
    int index,
    StandingsRow row,
    int total,
  )? rowColorBuilder;

  @override
  State<StandingsTable> createState() => _StandingsTableState();
}

class _StandingsTableState extends State<StandingsTable> {
  /// Index of the currently sorted column in the DataTable.
  /// 0 = Team, 1 = P, 2 = W, 3 = D, 4 = L, 5 = GD, 6 = GF, 7 = Pts
  int _sortCol = 7; // default sort by points

  /// Whether the sort is ascending or descending.
  bool _asc = false;

  /// Returns a sorted copy of the incoming rows based on the current sort state.
  List<StandingsRow> get _sorted {
    final rows = [...widget.rows];

    rows.sort((a, b) {
      int v;
      switch (_sortCol) {
        case 0: // Team
          v = a.teamName.compareTo(b.teamName);
          break;
        case 1: // Played
          v = a.mp.compareTo(b.mp);
          break;
        case 2: // Wins
          v = a.w.compareTo(b.w);
          break;
        case 3: // Draws
          v = a.d.compareTo(b.d);
          break;
        case 4: // Losses
          v = a.l.compareTo(b.l);
          break;
        case 5: // Goal difference
          v = a.gd.compareTo(b.gd);
          break;
        case 6: // Goals for
          v = a.gf.compareTo(b.gf);
          break;
        case 7: // Points
        default:
          v = a.pts.compareTo(b.pts);
      }
      // Flip sort order depending on [_asc].
      return _asc ? v : -v;
    });

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    final screenHeight = MediaQuery.of(context).size.height;
    // The table area will use at most 60% of the screen height.
    final maxTableHeight = screenHeight * 0.6;

    return Glass(
      // Glass.borderRadius is a double, so pass a radius, not a BorderRadius.
      borderRadius: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              // Let the table be at least as wide as the available width,
              // so it looks good on tablets too.
              minWidth: constraints.maxWidth,
              // Limit the height so vertical scrolling becomes possible.
              maxHeight: maxTableHeight,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  sortAscending: _asc,
                  sortColumnIndex: _sortCol,
                  columnSpacing: 18,
                  columns: [
                    _col('Team', 0),
                    _col('P', 1, numeric: true),
                    _col('W', 2, numeric: true),
                    _col('D', 3, numeric: true),
                    _col('L', 4, numeric: true),
                    _col('GD', 5, numeric: true),
                    _col('GF', 6, numeric: true),
                    _col('Pts', 7, numeric: true),
                  ],
                  rows: [
                    for (int i = 0; i < rows.length; i++)
                      _row(context, i, rows.length, rows[i]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Helper to create a sortable [DataColumn].
  DataColumn _col(String label, int index, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      onSort: (colIndex, ascending) {
        setState(() {
          _sortCol = colIndex;
          _asc = ascending;
        });
      },
    );
  }

  /// Build a single DataRow for the standings table.
  DataRow _row(
    BuildContext context,
    int i,
    int total,
    StandingsRow r,
  ) {
    Color? zoneColor;

    if (widget.rowColorBuilder != null) {
      zoneColor = widget.rowColorBuilder!(context, i, r, total);
    } else {
      // Default coloring:
      // - Top 2: green (champions zone)
      // - Next 2: primary tint (e.g. European qualifiers)
      final primary = Theme.of(context).colorScheme.primary;
      zoneColor = i < 2
          ? Colors.green.withOpacity(0.12)
          : i < 4
              ? primary.withOpacity(0.10)
              : Colors.transparent;
    }

    return DataRow(
      // In Flutter 3.24, WidgetStatePropertyAll works here.
      color: zoneColor != null ? WidgetStatePropertyAll(zoneColor) : null,
      cells: [
        DataCell(
          // Show position before the team name for clarity.
          Text(
            '${i + 1}. ${r.teamName}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(Text('${r.mp}')),
        DataCell(Text('${r.w}')),
        DataCell(Text('${r.d}')),
        DataCell(Text('${r.l}')),
        DataCell(Text('${r.gd}')),
        DataCell(Text('${r.gf}')),
        DataCell(
          Text(
            '${r.pts}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
