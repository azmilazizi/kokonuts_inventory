import 'dart:convert';

import 'package:http/http.dart' as http;

class ReceivingOptionsService {
  ReceivingOptionsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _optionsUrl = 'https://crm.kokonuts.my/api/v1/options';

  Future<ReceivingOptions> fetchReceivingOptions({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(_optionsUrl), headers: headers);
    } catch (error) {
      throw ReceivingOptionsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw ReceivingOptionsException(
        'Options request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ReceivingOptionsException('Unable to parse options response: $error');
    }

    return ReceivingOptions(
      lotNumberPrefix: _extractLotNumberPrefix(decoded),
      nextLotNumber: _extractNextLotNumber(decoded),
      inventoryReceivedNumberPrefix: _extractInventoryReceivedPrefix(decoded),
      nextInventoryReceivedNumber: _extractNextInventoryReceivedNumber(decoded),
    );
  }

  String? _extractLotNumberPrefix(dynamic source) {
    if (source is Map<String, dynamic>) {
      if (source['name'] == 'lot_number_prefix' && source.containsKey('value')) {
        return _asString(source['value']);
      }

      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'lot_number_prefix' ||
            key == 'lotnumberprefix' ||
            key == 'lot_prefix' ||
            key == 'lotprefix') {
          return _asString(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractLotNumberPrefix(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractLotNumberPrefix(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  int? _extractNextLotNumber(dynamic source) {
    if (source is Map<String, dynamic>) {
      if (source['name'] == 'next_lot_number' && source.containsKey('value')) {
        return _asInt(source['value']);
      }

      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'next_lot_number' ||
            key == 'nextlotnumber' ||
            key == 'next_lot' ||
            key == 'nextlot') {
          return _asInt(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractNextLotNumber(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractNextLotNumber(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  String? _extractInventoryReceivedPrefix(dynamic source) {
    if (source is Map<String, dynamic>) {
      if (source['name'] == 'inventory_received_number_prefix' &&
          source.containsKey('value')) {
        return _asString(source['value']);
      }

      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'inventory_received_number_prefix' ||
            key == 'inventoryreceivednumberprefix' ||
            key == 'inventory_received_prefix' ||
            key == 'inventoryreceivedprefix') {
          return _asString(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractInventoryReceivedPrefix(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractInventoryReceivedPrefix(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  int? _extractNextInventoryReceivedNumber(dynamic source) {
    if (source is Map<String, dynamic>) {
      if ((source['name'] == 'next_inventory_received_number' ||
              source['name'] == 'next_inventory_received_mumber') &&
          source.containsKey('value')) {
        return _asInt(source['value']);
      }

      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'next_inventory_received_number' ||
            key == 'next_inventory_received_mumber' ||
            key == 'nextinventoryreceivednumber' ||
            key == 'next_inventory_received') {
          return _asInt(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractNextInventoryReceivedNumber(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractNextInventoryReceivedNumber(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String? _asString(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return value?.toString();
  }
}

class ReceivingOptions {
  const ReceivingOptions({
    required this.lotNumberPrefix,
    required this.nextLotNumber,
    required this.inventoryReceivedNumberPrefix,
    required this.nextInventoryReceivedNumber,
  });

  final String? lotNumberPrefix;
  final int? nextLotNumber;
  final String? inventoryReceivedNumberPrefix;
  final int? nextInventoryReceivedNumber;
}

class ReceivingOptionsException implements Exception {
  ReceivingOptionsException(this.message);

  final String message;

  @override
  String toString() => 'ReceivingOptionsException: $message';
}
