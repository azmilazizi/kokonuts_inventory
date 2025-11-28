import 'dart:convert';

import 'package:http/http.dart' as http;

class VendorsService {
  VendorsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _vendorsUrl = 'https://crm.kokonuts.my/purchase/api/v1/vendors';

  Future<List<VendorSummary>> fetchVendors({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(_vendorsUrl), headers: headers);
    } catch (error) {
      throw VendorsServiceException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw VendorsServiceException(
        'Vendor request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw VendorsServiceException('Unable to parse vendor response: $error');
    }

    final Map<String, VendorSummary> vendorsByName = {};
    _collectVendors(decoded, vendorsByName);
    final sorted = vendorsByName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  void _collectVendors(dynamic source, Map<String, VendorSummary> results) {
    if (source is Map<String, dynamic>) {
      final name = _extractVendorName(source);
      final id = _extractVendorId(source);
      if (name != null && id != null) {
        final code = _extractVendorCode(source);
        results[name] = VendorSummary(id: id, name: name, code: code);
      }
      for (final value in source.values) {
        _collectVendors(value, results);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectVendors(item, results);
      }
    }
  }

  String? _extractVendorName(Map<String, dynamic> source) {
    const candidateKeys = [
      'name',
      'vendor_name',
      'vendorName',
      'company',
      'company_name',
      'companyName',
    ];
    for (final key in candidateKeys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _extractVendorCode(Map<String, dynamic> source) {
    const candidateKeys = [
      'vendor_code',
      'vendorCode',
      'code',
    ];
    for (final key in candidateKeys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _extractVendorId(Map<String, dynamic> source) {
    const candidateKeys = [
      'vendor_id',
      'vendorId',
      'id',
    ];
    for (final key in candidateKeys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is int) {
        return value.toString();
      }
    }
    return null;
  }
}

class VendorsServiceException implements Exception {
  VendorsServiceException(this.message);

  final String message;

  @override
  String toString() => 'VendorsServiceException: $message';
}

class VendorSummary {
  const VendorSummary({required this.id, required this.name, this.code});

  final String id;
  final String name;
  final String? code;
}
