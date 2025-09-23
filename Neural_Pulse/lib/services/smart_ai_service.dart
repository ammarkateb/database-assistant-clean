import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_database.dart';

class SmartAIService {
  static const String ollamaBaseUrl = 'http://192.168.8.155:11434';
  static const String modelName = 'phi3:mini';

  // Main AI response processor - uses local Phi-3 Mini LLM
  static Future<Map<String, dynamic>> processQuery(String query) async {
    try {
      final lowerQuery = query.toLowerCase();

      // Handle chart/visualization requests first - these need special handling
      if (_isChartRequest(lowerQuery)) {
        return await _handleChartRequest(query);
      }

      // For all other queries, get context from database and send to LLM
      final context = await _buildBusinessContext();
      final prompt = await _buildPrompt(query, context);

      // Try to get response from local Phi-3 Mini
      final response = await _queryLocalLLM(prompt);

      if (response != null) {
        return {
          'success': true,
          'message': response,
          'offline': false
        };
      } else {
        // Fallback to basic responses if LLM is unavailable
        return await _handleFallbackResponse(query);
      }

    } catch (e) {
      print('SmartAIService error: $e');
      return await _handleFallbackResponse(query);
    }
  }

  // Query the local Phi-3 Mini LLM via Ollama
  static Future<String?> _queryLocalLLM(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('$ollamaBaseUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': modelName,
          'prompt': prompt,
          'stream': false,
          'options': {
            'temperature': 0.7,
            'num_predict': 200,
          }
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response']?.toString().trim();
      } else {
        print('Ollama API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Failed to connect to local LLM: $e');
      return null;
    }
  }

  // Build business context from database
  static Future<String> _buildBusinessContext() async {
    try {
      final invoices = await LocalDatabase.getInvoices(1);

      if (invoices.isEmpty) {
        return "No invoice data available. This is a demo business analytics system.";
      }

      // Calculate basic metrics
      double totalRevenue = 0.0;
      Map<String, double> customerTotals = {};
      Map<String, double> monthlyTotals = {};

      final now = DateTime.now();
      final currentYear = now.year;

      for (final invoice in invoices) {
        final amount = (invoice['amount'] as num).toDouble();
        final customerName = invoice['customer_name'] as String? ?? 'Unknown';
        final createdAt = DateTime.tryParse(invoice['created_at'] ?? '');

        totalRevenue += amount;
        customerTotals[customerName] = (customerTotals[customerName] ?? 0.0) + amount;

        if (createdAt != null && createdAt.year == currentYear) {
          final monthKey = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}';
          monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0.0) + amount;
        }
      }

      final topCustomer = customerTotals.entries.isNotEmpty
          ? customerTotals.entries.reduce((a, b) => a.value > b.value ? a : b)
          : null;

      return """
Business Context:
- Total Revenue: \$${_formatNumber(totalRevenue)}
- Total Invoices: ${invoices.length}
- Top Customer: ${topCustomer?.key ?? 'None'} (\$${topCustomer != null ? _formatNumber(topCustomer.value) : '0'})
- Active Customers: ${customerTotals.length}
- Monthly Data Available: ${monthlyTotals.length} months in ${currentYear}
""";
    } catch (e) {
      return "Error accessing business data: $e";
    }
  }

  // Build comprehensive prompt for the LLM
  static Future<String> _buildPrompt(String userQuery, String context) async {
    return """
You are Neural Pulse, an AI business analytics assistant. You help analyze business data and provide insights.

${context}

User Question: ${userQuery}

Instructions:
- Be conversational and helpful
- Use the business context provided to give specific, relevant answers
- If asked about charts/visualizations, mention that you can create them
- Keep responses concise but informative (2-4 sentences)
- If you don't have specific data, acknowledge it but still be helpful
- For greetings, introduce yourself and your capabilities
- Always maintain a professional yet friendly tone

Response:""";
  }

  // Fallback response when LLM is unavailable
  static Future<Map<String, dynamic>> _handleFallbackResponse(String query) async {
    final lowerQuery = query.toLowerCase();

    if (_isGreeting(lowerQuery)) {
      return {
        'success': true,
        'message': 'Hello! I\'m your Neural Pulse AI assistant. I can help with business analytics, customer data, and sales insights. My local LLM seems to be unavailable, but I can still assist with basic queries.',
        'offline': true
      };
    }

    if (_isCustomerQuery(lowerQuery)) {
      return await _getCustomerInfo(query);
    }

    if (_isSalesQuery(lowerQuery)) {
      return await _getSalesInfo(query);
    }

    return {
      'success': true,
      'message': 'I\'m your business analytics assistant. My advanced AI is currently unavailable, but I can help with basic data queries. Try asking about customers, sales, or request a chart visualization.',
      'offline': true
    };
  }

  // Query type detection
  static bool _isGreeting(String query) {
    final greetings = ['hi', 'hello', 'hey', 'good morning', 'good afternoon', 'good evening'];
    return greetings.any((greeting) => query.contains(greeting));
  }

  static bool _isChartRequest(String query) {
    final chartTerms = ['chart', 'graph', 'bar', 'show me', 'visualize', 'plot', 'visualization', 'barchart'];
    return chartTerms.any((term) => query.contains(term));
  }

  static bool _isCustomerQuery(String query) {
    final customerTerms = ['customer', 'client', 'top customer', 'best customer', 'who is my'];
    return customerTerms.any((term) => query.contains(term));
  }

  static bool _isSalesQuery(String query) {
    final salesTerms = ['sales', 'revenue', 'money', 'earnings', '2025', 'monthly', 'total'];
    return salesTerms.any((term) => query.contains(term));
  }


  // Get customer info for fallback
  static Future<Map<String, dynamic>> _getCustomerInfo(String query) async {
    try {
      final invoices = await LocalDatabase.getInvoices(1);

      if (invoices.isEmpty) {
        return {
          'success': true,
          'message': 'No customer data available yet. Once you add invoices, I can analyze your customer information.',
          'offline': true
        };
      }

      Map<String, double> customerTotals = {};
      for (final invoice in invoices) {
        final customerName = invoice['customer_name'] as String? ?? 'Unknown';
        final amount = (invoice['amount'] as num).toDouble();
        customerTotals[customerName] = (customerTotals[customerName] ?? 0.0) + amount;
      }

      final topCustomer = customerTotals.entries.reduce((a, b) => a.value > b.value ? a : b);

      return {
        'success': true,
        'message': 'Your top customer is ${topCustomer.key} with \$${_formatNumber(topCustomer.value)} in total revenue. You have ${customerTotals.length} active customers.',
        'offline': true
      };
    } catch (e) {
      return {
        'success': true,
        'message': 'I can analyze customer data including top customers, spending patterns, and customer metrics.',
        'offline': true
      };
    }
  }

  // Get sales info for fallback
  static Future<Map<String, dynamic>> _getSalesInfo(String query) async {
    try {
      final invoices = await LocalDatabase.getInvoices(1);

      if (invoices.isEmpty) {
        return {
          'success': true,
          'message': 'No sales data available yet. Once you add invoices, I can provide detailed sales analytics.',
          'offline': true
        };
      }

      double totalRevenue = 0.0;
      final now = DateTime.now();
      double currentYearRevenue = 0.0;

      for (final invoice in invoices) {
        final amount = (invoice['amount'] as num).toDouble();
        totalRevenue += amount;

        final createdAt = DateTime.tryParse(invoice['created_at'] ?? '');
        if (createdAt != null && createdAt.year == now.year) {
          currentYearRevenue += amount;
        }
      }

      return {
        'success': true,
        'message': 'Total revenue: \$${_formatNumber(totalRevenue)}. This year (${now.year}): \$${_formatNumber(currentYearRevenue)} from ${invoices.length} invoices.',
        'offline': true
      };
    } catch (e) {
      return {
        'success': true,
        'message': 'I can analyze sales and revenue data including trends, totals, and performance metrics.',
        'offline': true
      };
    }
  }

  static Future<Map<String, dynamic>> _handleChartRequest(String query) async {
    final lowerQuery = query.toLowerCase();

    // Sales/revenue charts
    if (lowerQuery.contains('sales') || lowerQuery.contains('revenue') || lowerQuery.contains('2025') || lowerQuery.contains('monthly') || lowerQuery.contains('per month')) {
      return await _createSalesChart();
    }

    // Customer charts
    if (lowerQuery.contains('customer') || lowerQuery.contains('client')) {
      return await _createCustomerChart();
    }

    // Default chart suggestion
    return {
      'success': true,
      'message': 'I can create charts for:\n• Monthly sales/revenue\n• Top customers\n• Performance trends\n\nWhat would you like to visualize?',
      'offline': true
    };
  }

  static Future<Map<String, dynamic>> _createSalesChart() async {
    // Get real data or use sample data
    final invoices = await LocalDatabase.getInvoices(1);
    Map<String, double> monthlyData = {};

    if (invoices.isNotEmpty) {
      // Process real invoice data by month
      final now = DateTime.now();
      final currentYear = now.year;

      // Initialize all months to 0
      for (int i = 1; i <= 12; i++) {
        final monthName = _getMonthName(i);
        monthlyData[monthName] = 0.0;
      }

      // Aggregate invoice data by month
      for (final invoice in invoices) {
        final createdAt = DateTime.tryParse(invoice['created_at'] ?? '');
        if (createdAt != null && createdAt.year == currentYear) {
          final monthName = _getMonthName(createdAt.month);
          monthlyData[monthName] = (monthlyData[monthName] ?? 0.0) + (invoice['amount'] as num).toDouble();
        }
      }
    } else {
      // Use sample data to demonstrate functionality
      monthlyData = {
        'Jan': 15420.50,
        'Feb': 18750.25,
        'Mar': 22100.75,
        'Apr': 19850.00,
        'May': 24300.50,
        'Jun': 21900.25,
        'Jul': 26750.75,
        'Aug': 23400.00,
        'Sep': 28200.50,
        'Oct': 25800.25,
        'Nov': 30100.75,
        'Dec': 32500.00,
      };
    }

    final totalSales = monthlyData.values.fold(0.0, (sum, value) => sum + value);

    return {
      'success': true,
      'message': 'Here\'s your 2025 sales performance by month:\n\nTotal Revenue: \$${_formatNumber(totalSales)}\nBest Month: ${_getBestMonth(monthlyData)}\nAverage Monthly: \$${_formatNumber(totalSales / 12)}',
      'chart': {
        'type': 'bar',
        'title': '2025 Monthly Sales',
        'data': monthlyData,
        'color': '#64FFDA',
        'showValues': true,
      },
      'offline': true
    };
  }

  static Future<Map<String, dynamic>> _createCustomerChart() async {
    final invoices = await LocalDatabase.getInvoices(1);
    Map<String, double> customerData = {};

    if (invoices.isNotEmpty) {
      // Aggregate by customer
      for (final invoice in invoices) {
        final customerName = invoice['customer_name'] as String? ?? 'Unknown Customer';
        final amount = (invoice['amount'] as num).toDouble();
        customerData[customerName] = (customerData[customerName] ?? 0.0) + amount;
      }

      // Get top 5 customers
      final sortedCustomers = customerData.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      customerData = Map.fromEntries(sortedCustomers.take(5));
    } else {
      // Sample customer data
      customerData = {
        'Acme Corporation': 45750.50,
        'Tech Solutions Ltd': 38400.25,
        'Global Industries': 32100.75,
        'Startup Innovations': 28650.00,
        'Enterprise Partners': 24300.50,
      };
    }

    final topCustomer = customerData.entries.first;

    return {
      'success': true,
      'message': 'Here are your top customers:\n\nBest Customer: ${topCustomer.key} (\$${_formatNumber(topCustomer.value)})\nTotal Customers: ${customerData.length}\nTop 5 Revenue: \$${_formatNumber(customerData.values.fold(0.0, (sum, value) => sum + value))}',
      'chart': {
        'type': 'bar',
        'title': 'Top 5 Customers',
        'data': customerData,
        'color': '#FF6B9D',
        'showValues': true,
      },
      'offline': true
    };
  }


  // Utility methods
  static String _getMonthName(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month];
  }

  static String _getBestMonth(Map<String, double> monthlyData) {
    if (monthlyData.isEmpty) return 'N/A';
    return monthlyData.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  static String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    } else {
      return number.toStringAsFixed(2);
    }
  }
}