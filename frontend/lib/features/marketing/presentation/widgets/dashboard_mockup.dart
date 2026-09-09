import 'package:flutter/material.dart';

import '../marketing_colors.dart';

/// A miniature "laptop showing the admin dashboard" illustration, matching
/// the prototype's `.laptop > .screen` composition (sidebar nav + KPI cards
/// + a chart placeholder + an activity feed) - not a real screenshot, a
/// stylized recreation used purely as hero-section visual texture.
class DashboardMockup extends StatelessWidget {
  const DashboardMockup({super.key, this.width = 590});

  final double width;

  @override
  Widget build(BuildContext context) {
    final scale = width / 590;

    return Container(
      width: width,
      padding: EdgeInsets.all(9 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18 * scale),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.19),
            blurRadius: 55,
            offset: const Offset(0, 25),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10 * scale),
        child: SizedBox(
          height: 345 * scale,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(scale: scale),
              Expanded(child: _DashBody(scale: scale)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.scale});

  final double scale;

  static const _items = [
    ('⌂', 'Dashboard', true),
    ('☺', 'Students', false),
    ('☺', 'Teachers', false),
    ('✓', 'Attendance', false),
    ('▦', 'Academics', false),
    ('¤', 'Payments', false),
    ('🚌', 'Transport', false),
    ('✉', 'Communication', false),
    ('⚭', 'HR & Payroll', false),
    ('▥', 'Reports', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 125 * scale,
      color: const Color(0xFF10203D),
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 13 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎓 School365ai',
            style: TextStyle(color: Colors.white, fontSize: 11 * scale, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 15 * scale),
          // Scrollable, not just sized to fit: text-metric variance across
          // rendering backends (canvaskit/skwasm/different test harnesses)
          // means 10 lines at this font size doesn't reliably fit the
          // available height - this is decorative hero art, not real
          // navigation, so absorbing any overflow via scroll (never
          // actually seen) is preferable to a RenderFlex overflow error.
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in _items)
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.symmetric(vertical: 3 * scale),
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 7 * scale),
                      decoration: BoxDecoration(
                        color: item.$3 ? MarketingColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(7 * scale),
                      ),
                      child: Text(
                        '${item.$1}  ${item.$2}',
                        style: TextStyle(
                          color: item.$3 ? Colors.white : const Color(0xFFCBD5E1),
                          fontSize: 8 * scale,
                          height: 1.1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashBody extends StatelessWidget {
  const _DashBody({required this.scale});

  final double scale;

  static const _kpis = [
    ('Total Students', '1,248', '↑ 5%'),
    ('Teachers', '86', '↑ 2%'),
    ('Present Today', '1,162', '93%'),
    ('Fees Collected', '\$28,450', '↑ 12%'),
  ];

  static const _activity = [
    'Fee payment received',
    'New student admitted',
    'Leave request approved',
    'Bus trip completed',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarketingColors.background,
      padding: EdgeInsets.all(15 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Good Morning, Principal!',
                style: TextStyle(fontSize: 9 * scale, fontWeight: FontWeight.w800, color: MarketingColors.text),
              ),
              Text(
                'Admin · Principal',
                style: TextStyle(fontSize: 9 * scale, color: MarketingColors.subtle),
              ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Row(
            children: [
              for (final kpi in _kpis)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: kpi == _kpis.last ? 0 : 7 * scale),
                    padding: EdgeInsets.all(9 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: MarketingColors.border),
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kpi.$1,
                          style: TextStyle(fontSize: 7 * scale, color: MarketingColors.subtle),
                        ),
                        Text(
                          kpi.$2,
                          style: TextStyle(
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w800,
                            color: MarketingColors.text,
                          ),
                        ),
                        Text(
                          kpi.$3,
                          style: TextStyle(fontSize: 6 * scale, color: MarketingColors.success),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 9 * scale),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 13,
                  child: Container(
                    margin: EdgeInsets.only(right: 8 * scale),
                    padding: EdgeInsets.all(9 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: MarketingColors.border),
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance Overview',
                          style: TextStyle(fontSize: 8 * scale, color: MarketingColors.text),
                        ),
                        SizedBox(height: 8 * scale),
                        Expanded(
                          child: CustomPaint(size: Size.infinite, painter: _TrendLinePainter()),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Container(
                    padding: EdgeInsets.all(9 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: MarketingColors.border),
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Activity',
                          style: TextStyle(fontSize: 8 * scale, color: MarketingColors.text),
                        ),
                        SizedBox(height: 6 * scale),
                        for (final activity in _activity)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 4 * scale),
                            child: Text(
                              '✓ $activity',
                              style: TextStyle(fontSize: 7 * scale, color: MarketingColors.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  static const _points = [
    Offset(0, 0.75),
    Offset(0.11, 0.65),
    Offset(0.2, 0.72),
    Offset(0.31, 0.48),
    Offset(0.42, 0.58),
    Offset(0.54, 0.36),
    Offset(0.65, 0.45),
    Offset(0.78, 0.25),
    Offset(0.88, 0.4),
    Offset(1, 0.12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MarketingColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < _points.length; i++) {
      final point = Offset(_points[i].dx * size.width, _points[i].dy * size.height);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
