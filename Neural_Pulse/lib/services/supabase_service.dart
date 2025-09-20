import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient? _client;

  // Your Supabase configuration (from backend/db_assistant.py)
  static const String supabaseUrl = 'https://xjcsrfbdtkizmpvvvoot.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhqY3NyZmJkdGtpem1wdnZ2b290Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjU4MTAzNzYsImV4cCI6MjA0MTM4NjM3Nn0.XwPJGYKvJ9_lLKaNnpCfKm8gLdI4K3QPMJOOeX8bGLo'; // We'll need to get this

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      _client = Supabase.instance.client;
      print('✅ Supabase initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize Supabase: $e');
      throw e;
    }
  }

  static SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase not initialized. Call SupabaseService.initialize() first.');
    }
    return _client!;
  }

  // Get invoices from your Supabase database
  static Future<List<Map<String, dynamic>>> getInvoices({int? userId}) async {
    try {
      var query = client.from('invoices').select('''
        id,
        customer_id,
        invoice_date,
        total_amount,
        status,
        created_at,
        customers:customer_id (
          id,
          customer_name,
          email,
          phone
        )
      ''');

      if (userId != null) {
        // Filter by user if needed - adjust based on your schema
        query = query.eq('user_id', userId);
      }

      final response = await query.order('invoice_date', ascending: false);

      print('✅ Fetched ${response.length} invoices from Supabase');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching invoices: $e');
      return [];
    }
  }

  // Get customers from your Supabase database
  static Future<List<Map<String, dynamic>>> getCustomers({int? userId}) async {
    try {
      var query = client.from('customers').select('''
        id,
        customer_name,
        email,
        phone,
        created_at,
        invoices:customer_id (
          total_amount,
          invoice_date,
          status
        )
      ''');

      final response = await query.order('customer_name', ascending: true);

      print('✅ Fetched ${response.length} customers from Supabase');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching customers: $e');
      return [];
    }
  }

  // Get products from your Supabase database
  static Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final response = await client.from('products').select('''
        id,
        product_name,
        category,
        unit_price,
        current_stock,
        created_at
      ''').order('product_name', ascending: true);

      print('✅ Fetched ${response.length} products from Supabase');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching products: $e');
      return [];
    }
  }

  // Get top customers with revenue calculations
  static Future<List<Map<String, dynamic>>> getTopCustomers({int limit = 10}) async {
    try {
      final response = await client.rpc('get_top_customers', params: {
        'result_limit': limit
      });

      if (response != null) {
        print('✅ Fetched top ${response.length} customers from Supabase');
        return List<Map<String, dynamic>>.from(response);
      }

      // Fallback: manual calculation if RPC doesn't exist
      return await _calculateTopCustomersManually(limit);
    } catch (e) {
      print('❌ Error fetching top customers, trying manual calculation: $e');
      return await _calculateTopCustomersManually(limit);
    }
  }

  // Manual calculation of top customers if RPC doesn't exist
  static Future<List<Map<String, dynamic>>> _calculateTopCustomersManually(int limit) async {
    try {
      final invoices = await getInvoices();

      // Group by customer and calculate totals
      final customerTotals = <String, Map<String, dynamic>>{};

      for (final invoice in invoices) {
        final customerId = invoice['customer_id']?.toString() ?? 'unknown';
        final customerName = invoice['customers']?['customer_name'] ?? 'Unknown Customer';
        final amount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;

        if (customerTotals.containsKey(customerId)) {
          customerTotals[customerId]!['total'] += amount;
          customerTotals[customerId]!['invoice_count']++;
        } else {
          customerTotals[customerId] = {
            'customer_id': customerId,
            'customer_name': customerName,
            'total': amount,
            'invoice_count': 1
          };
        }
      }

      // Sort by total and take top N
      final sortedCustomers = customerTotals.values.toList()
        ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

      return sortedCustomers.take(limit).toList();
    } catch (e) {
      print('❌ Error in manual customer calculation: $e');
      return [];
    }
  }

  // Get monthly revenue data
  static Future<List<Map<String, dynamic>>> getMonthlyRevenue({int months = 12}) async {
    try {
      final response = await client.rpc('get_monthly_revenue', params: {
        'months_back': months
      });

      if (response != null) {
        print('✅ Fetched monthly revenue data from Supabase');
        return List<Map<String, dynamic>>.from(response);
      }

      // Fallback: manual calculation
      return await _calculateMonthlyRevenueManually(months);
    } catch (e) {
      print('❌ Error fetching monthly revenue, trying manual calculation: $e');
      return await _calculateMonthlyRevenueManually(months);
    }
  }

  // Manual calculation of monthly revenue
  static Future<List<Map<String, dynamic>>> _calculateMonthlyRevenueManually(int months) async {
    try {
      final invoices = await getInvoices();

      // Group by month and calculate totals
      final monthlyTotals = <String, double>{};

      for (final invoice in invoices) {
        final dateStr = invoice['invoice_date'] as String?;
        if (dateStr != null) {
          final date = DateTime.parse(dateStr);
          final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
          final amount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;

          monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + amount;
        }
      }

      // Convert to list format
      final result = monthlyTotals.entries.map((entry) => {
        'month': entry.key,
        'total_revenue': entry.value
      }).toList();

      // Sort by month
      result.sort((a, b) => a['month'].compareTo(b['month']));

      return result.take(months).toList();
    } catch (e) {
      print('❌ Error in manual monthly revenue calculation: $e');
      return [];
    }
  }

  // Test connection to your Supabase
  static Future<bool> testConnection() async {
    try {
      final response = await client.from('users').select('count').count(CountOption.exact);
      print('✅ Supabase connection test successful');
      return true;
    } catch (e) {
      print('❌ Supabase connection test failed: $e');
      return false;
    }
  }
}