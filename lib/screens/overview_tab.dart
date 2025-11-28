import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:math' as math;

import '../app/app_state.dart';
import '../services/overview_service.dart';

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key, required this.appState});

  final AppState appState;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  late final OverviewService _service;

  late DateTime _startDate;
  late DateTime _endDate;

  bool _isLoading = false;
  bool _isChartLoading = false;
  String? _errorMessage;
  MoneyOutSummary? _summary;
  ExpensesPieChartData? _expensesPercentage;
  String _accountingMethod = 'payment'; // 'payment' (Cash) or 'issued' (Accrual)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    // Last day of current month: 0th day of next month
    _endDate = DateTime(now.year, now.month + 1, 0);

    _service = OverviewService();
    _fetchSummary();
    _fetchCharts();
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await _service.fetchMoneyOutSummary(
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
        type: _accountingMethod,
        headers: {
          'Authorization': 'Bearer ${widget.appState.authToken}',
        },
      );
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCharts() async {
    setState(() {
      _isChartLoading = true;
    });

    try {
      final data = await _service.fetchExpensesPercentageByType(
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
        type: _accountingMethod,
        headers: {
          'Authorization': 'Bearer ${widget.appState.authToken}',
        },
      );
      if (mounted) {
        setState(() {
          _expensesPercentage = data;
          _isChartLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // Silently fail or log error for charts, so it doesn't block the whole UI
        // or show a small error in the chart section
        setState(() {
          _isChartLoading = false;
        });
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchSummary();
      _fetchCharts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('MMM dd, yyyy');

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchSummary();
        await _fetchCharts();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Range & Total Spent Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Accounting Method Dropdown
                  Row(
                    children: [
                      Text(
                        'Accounting Method: ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _accountingMethod,
                        dropdownColor: theme.colorScheme.primaryContainer,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                        underline: Container(
                          height: 1,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _accountingMethod = newValue;
                            });
                            _fetchCharts();
                            _fetchSummary();
                          }
                        },
                        items: const [
                          DropdownMenuItem(
                            value: 'payment',
                            child: Text('Cash'),
                          ),
                          DropdownMenuItem(
                            value: 'issued',
                            child: Text('Accrual'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Date Range Filter
                  InkWell(
                    onTap: _selectDateRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 4.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${dateFormatter.format(_startDate)} - ${dateFormatter.format(_endDate)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Total Spent Header
                  Text(
                    'Total Spent',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isLoading)
                     SizedBox(
                       height: 40,
                       width: 40,
                       child: CircularProgressIndicator(
                         color: theme.colorScheme.onPrimaryContainer,
                       ),
                     )
                  else if (_summary != null)
                    Text(
                      _summary!.totalSpent,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  else
                    Text(
                      '--',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Transaction Summary Section
            Text(
              'Transaction Summary',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_summary != null)
              _TransactionSummarySection(summary: _summary!)
            else if (!_isLoading)
              const Center(child: Text('No data available')),

            const SizedBox(height: 32),

            // Expenses by Type Section
            Text(
              'Expenses by Type',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_isChartLoading)
              const Center(child: CircularProgressIndicator())
            else if (_expensesPercentage != null)
              _ExpensesByTypeSection(data: _expensesPercentage!, accountingMethod: _accountingMethod)
            else
              const Center(child: Text('No chart data available')),
          ],
        ),
      ),
    );
  }
}

class _TransactionSummarySection extends StatelessWidget {
  const _TransactionSummarySection({required this.summary});

  final MoneyOutSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Simple breakpoint logic: if width > 600, use Row, else Column
        final isLargeScreen = constraints.maxWidth > 600;

        final cards = [
          _SummaryCard(
            title: 'Purchase Orders',
            count: summary.purchaseOrders.count,
            total: summary.purchaseOrders.total,
            icon: Icons.shopping_cart,
          ),
          _SummaryCard(
            title: 'Expenses',
            count: summary.expenses.count,
            total: summary.expenses.total,
            icon: Icons.receipt,
          ),
          _SummaryCard(
            title: 'Bills',
            count: summary.bills.count,
            total: summary.bills.total,
            icon: Icons.description,
          ),
        ];

        if (isLargeScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards.map((c) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: c,
            ))).toList(),
          );
        } else {
          return Column(
            children: cards.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: c,
            )).toList(),
          );
        }
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.count,
    required this.total,
    required this.icon,
  });

  final String title;
  final int count;
  final String total;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Number of Transaction',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Spent',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Text(
                  total,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpensesByTypeSection extends StatelessWidget {
  const _ExpensesByTypeSection({required this.data, required this.accountingMethod});

  final ExpensesPieChartData data;
  final String accountingMethod;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth > 900;
        final isMediumScreen = constraints.maxWidth > 600;

        final charts = [
          _PieChartCard(
            title: 'Purchase Order by Item',
            items: data.purchaseOrderByItem,
            accountingMethod: accountingMethod,
          ),
          _PieChartCard(
            title: 'Expenses by Category',
            items: data.expensesByCategory,
            accountingMethod: accountingMethod,
          ),
          _PieChartCard(
            title: 'Bill by Account',
            items: data.billByAccount,
            accountingMethod: accountingMethod,
          ),
        ];

        if (isLargeScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: charts.map((c) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: c,
            ))).toList(),
          );
        } else if (isMediumScreen) {
          // 2 columns
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: charts.map((c) => SizedBox(
              width: (constraints.maxWidth - 32) / 2, // 32 = spacing + padding
              child: c,
            )).toList(),
          );
        } else {
          return Column(
            children: charts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: c,
            )).toList(),
          );
        }
      },
    );
  }
}

class _PieChartCard extends StatelessWidget {
  const _PieChartCard({
    required this.title,
    required this.items,
    required this.accountingMethod,
  });

  final String title;
  final List<ChartItem> items;
  final String accountingMethod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.simpleCurrency(name: ''); // Using '' to avoid symbol if needed or use default
    final sortedItems = List<ChartItem>.from(items)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Limit legend to top 5 for better UI, or maybe scrollable
    final displayItems = sortedItems.take(5).toList();

    final noDataMessage = accountingMethod == 'payment' ? 'No Payment' : 'No Outstanding';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              width: double.infinity,
              child: items.isEmpty
                  ? Center(child: Text(noDataMessage, style: theme.textTheme.bodyMedium))
                  : _PieChart(
                      items: items,
                      colors: const [
                        Colors.blue,
                        Colors.red,
                        Colors.green,
                        Colors.orange,
                        Colors.purple,
                        Colors.teal,
                        Colors.pink,
                        Colors.amber,
                        Colors.indigo,
                        Colors.cyan,
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            if (displayItems.isNotEmpty)
              Column(
                children: displayItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final color = [
                    Colors.blue,
                    Colors.red,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.teal,
                    Colors.pink,
                    Colors.amber,
                    Colors.indigo,
                    Colors.cyan,
                  ][index % 10];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.label.isEmpty ? 'Unknown' : item.label,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          currencyFormat.format(item.value),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  final List<ChartItem> items;
  final List<Color> colors;

  const _PieChart({
    required this.items,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return CustomPaint(
          size: size,
          painter: _PieChartPainter(
            items: items,
            colors: colors,
          ),
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<ChartItem> items;
  final List<Color> colors;

  _PieChartPainter({
    required this.items,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    double startAngle = -math.pi / 2;
    double totalValue = items.fold(0, (sum, item) => sum + item.value);

    if (totalValue == 0) return;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final sweepAngle = (item.value / totalValue) * 2 * math.pi;

      paint.color = colors[i % colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // Draw percentage text on the slice
      if (item.percentage >= 5) { // Only draw if slice is big enough
        final middleAngle = startAngle + sweepAngle / 2;
        // Position text slightly inwards (0.7 radius)
        final textRadius = radius * 0.7;
        final dx = center.dx + textRadius * math.cos(middleAngle);
        final dy = center.dy + textRadius * math.sin(middleAngle);

        final percentageText = '${item.percentage.toStringAsFixed(0)}%';

        final textSpan = TextSpan(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(blurRadius: 2, color: Colors.black45, offset: Offset(1, 1))
            ],
          ),
          text: percentageText,
        );

        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();

        final offset = Offset(
          dx - textPainter.width / 2,
          dy - textPainter.height / 2,
        );

        textPainter.paint(canvas, offset);
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.items != items;
  }
}
